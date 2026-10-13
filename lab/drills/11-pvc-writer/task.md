### Claim storage and write to it

In namespace `{{NS}}`, claim **{{SIZE}}Gi** of `ReadWriteOnce` storage from
StorageClass `nfs-csi` as PVC **`{{PVC}}`**. Run Pod **`{{POD}}`**
(`busybox:1.37`) that mounts it at `/data`, writes `{{WORD}}` into
`/data/{{FILE}}.txt`, and keeps running.

**Time budget:** 3:00
