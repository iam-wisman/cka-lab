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

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Determine the reason for Pod failure](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/)
- [Resource management for Pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Pod lifecycle: container states](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-states)

## Cleaning up

After `lab check` passes, run **`lab cleanup 29`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace ts-apps
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" and .spec.claimRef.namespace=="ts-apps") | .metadata.name' | xargs -r kubectl delete pv
ssh nfs sudo rm -rf /srv/nfs/k8s/ts-apps
```

## Restarting this lab

Run the cleanup above first (it removes the Retain volume left by `db-data`), then:

```bash
lab start 29
```

This deletes namespace `ts-apps` and recreates the starting objects, so you get the
original broken or empty state back.
