# Lab 05: Join two more control planes and two workers

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Implement and configure a highly-available control plane ·
Create and manage Kubernetes clusters using kubeadm
**Suggested time:** 60 minutes · **Start with:** `lab start 05`

## Context

`cp1` runs a single-member control plane behind the load balancer. Grow it to
three stacked control-plane nodes (three API servers, three etcd members) and
add both workers. `lab start 05` also simulates a busy cluster: there may be
certificate requests waiting that you didn't expect.

## Tasks

1. **Control planes.** Join `cp2` and `cp3` as control-plane nodes. The
   certificates uploaded in lab 03 have most likely expired by now; get the
   new node(s) the shared certificates **without copying any files by hand**.
   Each must advertise its own address (`10.10.10.12`, `10.10.10.13`).

2. **Workers.** Join `worker1` and `worker2` as worker nodes.

3. **Kubelet serving certificates.** Every new node requests a serving
   certificate (lab 03). Approve every **legitimate** kubelet serving request
   and **deny** anything else. A legitimate request comes from the node itself
   and asks only for that node's own name and address. After this,
   `kubectl logs` must work for a pod on every node.

4. **Roles and topology.** Label the nodes:

   | Node | `node-role.kubernetes.io/worker` | `topology.kubernetes.io/zone` |
   |---|---|---|
   | cp1 | no | `zone-a` |
   | cp2 | no | `zone-b` |
   | cp3 | no | `zone-c` |
   | worker1 | yes (empty value) | `zone-a` |
   | worker2 | yes (empty value) | `zone-b` |

   Control-plane nodes keep their `NoSchedule` taint.

5. **HA is real.** etcd must have exactly three voting members, `cp1`, `cp2`
   and `cp3`, all healthy, and all three API servers must be **UP** in the
   load balancer.

6. **Save your work.** When everything is green, take a snapshot. Later labs
   assume this cluster, and you'll want to come back to it:

   ```
   lab snapshot cluster-ready
   ```

## Grading

```
lab check 05
```

## Notes

- `kubeadm token create --print-join-command` prints the join command for
  workers. For control planes, look at `kubeadm init phase --help`.
- To query etcd, use the `etcdctl` inside the etcd static pod
  (`kubectl -n kube-system exec etcd-cp1 -- etcdctl ...`). It needs the
  endpoint and the three certificate flags; the etcd manifest has the paths.
- Optional resilience drill, after the snapshot: `sudo systemctl stop kubelet`
  and stop the API server container on `cp1` (or power `cp1` off from
  Proxmox), then confirm `kubectl get nodes` still works from `jump`.
  Restore afterwards.

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Creating highly available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [kubeadm join](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/)
- [kubeadm token](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/)
- [Certificate signing requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [Well-known labels, annotations and taints](https://kubernetes.io/docs/reference/labels-annotations-taints/)
- [Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

## Cleaning up

`lab cleanup 05` has nothing to remove here.

Approved and denied CSRs are garbage-collected by the cluster after an hour. Nothing else to remove. Take the snapshot the lab asks for, if you haven't:

```bash
lab snapshot cluster-ready
```

**Keep:** Everything. This is the cluster every later lab builds on.

## Restarting this lab

This lab changes the nodes themselves, so the only clean restart is a
snapshot. Take one **before** you start:

```bash
lab snapshot before-05
# ... attempt the lab ...
lab reset before-05        # all VMs roll back; reconnect to jump after ~1 minute
```

If you didn't take one, `lab reset` to a snapshot from after lab 04 (e.g. `after-04`), or rebuild from lab 01. Un-joining nodes by hand (`kubeadm reset` on each, `kubectl delete node`, `etcdctl member remove`) is possible but easy to get wrong.

The forged CSR comes back with `lab start 05`.
