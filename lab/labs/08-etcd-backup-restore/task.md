# Lab 08: Back up etcd, survive a disaster, restore a 3-member etcd cluster

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Manage the lifecycle of Kubernetes clusters · Implement and configure
a highly-available control plane · Troubleshoot cluster components
**Suggested time:** 90 minutes · **Start with:** `lab start 08`

> **Snapshot first:** `lab snapshot before-08`. A botched etcd restore can
> leave the cluster unrecoverable, and that's part of the lesson.

## Context

Everything the cluster knows lives in etcd. Here it's **stacked**: one etcd
member on each control plane, forming one 3-member cluster. The exam usually
asks you to restore a single-member etcd; this lab makes you restore all
three, which forces you to understand what a restore really creates.

`lab start 08` creates namespace `ledger` with data the business can't lose.

## Tasks

1. **Tools.** On `cp1`, install `etcdctl` and `etcdutl` into `/usr/local/bin`
   at **exactly the same version** as the etcd your cluster runs. (Ubuntu's
   `etcd-client` package is the wrong version. Use the etcd release tarball.)

2. **Back up.** Take a snapshot of etcd from `cp1`'s member to
   **`/var/backups/etcd/ledger.db`** on `cp1`, authenticating with etcd's
   client certificates. Check its integrity and record the output of
   `etcdutl snapshot status ... -w table` in `/var/backups/etcd/ledger.status`.
   Then copy the snapshot **off the node** to `/home/student/backups/ledger.db` on `jump`.

3. **Disaster.** Run `lab start 08 disaster`. It deletes namespace `ledger`
   and creates namespace `intruder`.

4. **Restore.** Bring the cluster back to the moment of your snapshot:
   - restore **every** member from the snapshot as a **new** etcd cluster.
     Don't recreate the deleted objects by hand: the grader checks they're the
     *original* objects.
   - each member's restored data must live in **`/var/lib/etcd-from-backup`**
     on its node, and its static pod must use it
   - when you're done: 3 healthy members (`cp1`, `cp2`, `cp3`), namespace
     `ledger` with all its data, no `intruder`, and every node `Ready`

## Grading

```
lab check 08
```

## Notes

- `etcdctl snapshot save` talks to a running member over the network;
  `etcdutl snapshot restore` works on files and needs no running etcd.
- A restore writes a **new data directory** with **new cluster membership**.
  Think about what that means for three members restored separately: what
  must every member agree on? Read `etcdutl snapshot restore --help`.
- Stop the API servers and etcd on **all** control planes before bringing any
  restored member up. The kubelet stops a static pod when you move its manifest
  out of `/etc/kubernetes/manifests/`.
- After a restore, restart kube-controller-manager, kube-scheduler and the
  kubelets so they don't act on stale cached state.

## Cleaning up

After `lab check` passes:

```bash
kubectl delete namespace ledger
rm -rf ~/backups
```

Optional: each control plane still has its **old**, now unused etcd data in
`/var/lib/etcd`. Only remove it after confirming the manifest points at the
restored directory, or you'll delete the live database:

```bash
for n in cp1 cp2 cp3; do
  ssh $n "sudo grep -q 'path: /var/lib/etcd-from-backup' /etc/kubernetes/manifests/etcd.yaml && sudo rm -rf /var/lib/etcd && echo $n: removed old /var/lib/etcd"
done
```

**Keep:** `etcdctl`/`etcdutl` in `/usr/local/bin` on cp1 (mock exam 1 uses them), and `/var/backups/etcd/ledger.db`.

## Restarting this lab

**After a successful restore** you can repeat the whole exercise:

```bash
lab start 08                # (re)creates namespace ledger and records its object IDs
# back up again, then: lab start 08 disaster, then restore
```

The restore procedure stops etcd on all three control planes first, so at that
point you can delete and recreate `/var/lib/etcd-from-backup` on each node.

**After a failed restore** (etcd won't form quorum, API servers down), reset
to the snapshot the lab told you to take:

```bash
lab reset before-08
```
