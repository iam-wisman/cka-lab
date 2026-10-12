## Task 15 (5 %) · Storage

### Persistent scratch space

In namespace `e1-t15` create PVC **`scratch`** (500Mi, ReadWriteOnce, class
`nfs-csi`) and Pod **`writer`** (`busybox:1.37`) that mounts it at `/scratch`
and writes `exam1` to `/scratch/marker` before sleeping. The file must exist
on the volume.
