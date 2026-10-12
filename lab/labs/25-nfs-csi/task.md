# Lab 25: NFS server from a raw disk, the NFS CSI driver, dynamic provisioning

**Domain:** Storage (10%)
**Curriculum:** Implement storage classes and dynamic volume provisioning ·
Understand extension interfaces (CSI)
**Suggested time:** 60 minutes · **Start with:** `lab start 25`

## Part A: the NFS server (`ssh nfs`)

`nfs` has a blank 60 GB second disk.

1. Give it a **GPT** partition table with **one partition** using the whole
   disk, formatted **XFS** with the filesystem label **`nfsdata`**.
2. Mount it at **`/srv/nfs`**, persistently, referencing the filesystem by
   **UUID** in `/etc/fstab` (not the device name: names can change between boots).
3. Install the kernel NFS server and export **`/srv/nfs/k8s`** to
   `10.10.10.0/24`, read-write, synchronous writes, no subtree checking, and
   **without root squashing** (the CSI driver creates directories as root).
4. On **every Kubernetes node**, install what's needed to mount NFS.

## Part B: the CSI driver

1. Install the **`csi-driver-nfs`** Helm chart **v4.13.5** from
   `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts`,
   release `csi-driver-nfs`, namespace `kube-system`.
2. Its CSIDriver object `nfs.csi.k8s.io` must exist, and the node plugin must
   run on **all five** nodes.

## Part C: the StorageClass

**`nfs-csi`**:

| Setting | Value |
|---|---|
| provisioner | `nfs.csi.k8s.io` |
| server / share | `10.10.10.30` / `/srv/nfs/k8s` |
| directory per volume | `<namespace>/<pvc-name>` (use the driver's templating) |
| reclaim policy | **Retain** |
| binding | immediate |
| expansion | allowed |
| mount options | NFS version **4.1** |
| default class | **yes**, and the **only** default in the cluster |

## Part D: prove it

In namespace `storage`:

1. PVC **`shared`**, 2Gi, **ReadWriteMany**, no `storageClassName` field (it
   must get the default).
2. Deployment **`writers`** (2 replicas, `busybox:1.37`) mounting it at `/data`,
   the two replicas on **different nodes**, each appending its pod name to
   `/data/log.txt` every 5 seconds.
3. On the `nfs` host, `/srv/nfs/k8s/storage/shared/log.txt` contains lines
   from **both** pods.

## Grading

```
lab check 25
```
