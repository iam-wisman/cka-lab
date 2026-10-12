## Task 15 (5 %) · Storage

### Bind to a prepared volume

On `worker1`, the directory `/mnt/e2-data` holds data. Create PersistentVolume
**`e2-data`** (1Gi, ReadWriteOnce, hostPath `/mnt/e2-data`, storage class name
`manual`, reclaim policy Retain), and PVC **`e2-data`** in namespace `e2-t15`
that binds to it. Pod **`viewer`** (`busybox:1.37`) mounts it at `/data`;
`/data/README` must be readable.
