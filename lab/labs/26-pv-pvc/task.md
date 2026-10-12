# Lab 26: PV/PVC lifecycle

**Domain:** Storage (10%)
**Curriculum:** Manage persistent volumes and persistent volume claims ·
Configure volume types, access modes and reclaim policies
**Suggested time:** 60 minutes · **Start with:** `lab start 26` · **Namespace:** `pv-lab`

## Tasks

1. **Recover a Released volume.** PV `archive-pv` (reclaim policy Retain)
   held business data for a PVC that someone deleted; it's now `Released`.
   Bind it to a **new** PVC **`archive`** in `pv-lab` **without deleting or
   recreating the PV** (the data must stay where it is), and make sure no
   other claim can grab it. Pod **`reader`** (`busybox:1.37`, `sleep infinity`)
   mounts it at `/archive`; `/archive/important.txt` must be readable.

2. **A local volume.** On `worker1` create `/mnt/disks/vol1`. Create:
   - StorageClass **`local-storage`**: no dynamic provisioning, and binding
     delayed until a pod uses the claim
   - PV **`local-vol1`**: 1Gi, ReadWriteOnce, that directory, usable only on
     `worker1`
   - PVC **`fast`** (1Gi, `local-storage`); it must stay `Pending` until used
   - Pod **`fast-consumer`** (`busybox:1.37`, `sleep infinity`) using `fast`
     at `/fast`, **with no node selection of its own**. It must land on worker1.

3. **Exactly one pod.** PVC **`exclusive`** (1Gi, `nfs-csi`) that **only one
   pod in the whole cluster** may use at a time (not just one node). Pod
   **`solo`** uses it and runs; pod **`second`** uses it too and must be
   refused by the scheduler.

4. **Grow a volume.** PVC **`growing`** exists at 1Gi. Expand it to **3Gi**
   in place.

5. **StatefulSet storage retention.** StatefulSet **`ledger`** (3 replicas,
   `busybox:1.37`, `sleep infinity`, headless Service `ledger`) with a
   per-replica 1Gi `nfs-csi` volume named `data` at `/data`. Its PVCs must be
   **deleted when the StatefulSet is deleted**, but **kept when it scales
   down**. Then scale it to **2** replicas.

## Grading

```
lab check 26
```
