# Lab 29: Troubleshoot seven broken workloads

**Domain:** Troubleshooting (30%)
**Suggested time:** 60 minutes · **Start with:** `lab start 29` · **Namespace:** `ts-apps`
**Needs:** lab 25 (StorageClass `nfs-csi`)

## Situation

Seven Deployments in `ts-apps` are broken: `web`, `worker`, `cache`, `db`,
`batch`, `api` and `crasher`. Each has its own fault.

## Tasks

Make **every** Deployment fully available, with these constraints:

- `worker-config` is owned by the platform team: **don't modify the
  ConfigMap**; fix the consumer.
- `cache` must run on a **worker** node (any worker), not wherever it lands.
- `db` must keep a PVC named **`db-data`**, now provisioned by `nfs-csi`.
- `batch` really does need its 60 MiB dataset in memory: give it a memory
  limit of **128Mi**, and don't touch its command.
- `api` must stay probed for readiness, on the right port. Service `api`
  must have endpoints and answer `api ok` inside the cluster.
- Keep every image except where an image is the fault.

## Grading

```
lab check 29
```

## Notes

- `kubectl get pods` → STATUS tells you the category; `kubectl describe pod`
  (events) and `kubectl logs --previous` tell you the cause.
- Some fields are immutable. You may have to delete and recreate an object.
