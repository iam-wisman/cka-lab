# Lab 18: ResourceQuota, LimitRange, PriorityClass and static pods

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Configure Pod admission and scheduling (limits, node affinity, etc.)
**Suggested time:** 55 minutes · **Start with:** `lab start 18`

## Part A: a fair share for team-a (namespace `team-a`)

1. **ResourceQuota `compute`**: total requests `cpu: 2`, `memory: 2Gi`;
   total limits `cpu: 4`, `memory: 4Gi`; at most **10** pods and **3**
   Deployments; **no** NodePort Services at all.
2. **LimitRange `container-defaults`** for containers:
   - default request `cpu: 100m`, `memory: 128Mi`
   - default limit `cpu: 500m`, `memory: 256Mi`
   - no container may ask for more than `cpu: 1` / `memory: 1Gi` (limit)
3. Deployment **`burst`**, 3 replicas of `nginx:1.27-alpine` with **no
   resources in its spec**: all 3 pods must run, with the defaults applied.
4. Demonstrate the quota: `kubectl -n team-a create service nodeport probe --tcp=80`
   must be **rejected**, and so must a pod asking for a `2` CPU limit.

## Part B: priorities

1. PriorityClass **`critical-batch`**: value `1000000`, may preempt lower
   priority pods, not the global default.
2. PriorityClass **`best-effort-batch`**: value `-10`, must **never** preempt
   anything.
3. Pod **`ingest`** in `team-a` (`busybox:1.37`, `sleep infinity`, requests
   `50m`/`32Mi`, limits `100m`/`64Mi`) running with `critical-batch`.
   Confirm its resolved `.spec.priority`.

## Part C: a static pod

1. On **worker1**, find where the kubelet reads static pod manifests (from
   its configuration, not from memory) and write the path to
   `~/answers/18-static-path.txt`.
2. Make worker1's kubelet run a static Pod **`static-web`** (`nginx:1.27-alpine`)
   in namespace `default`.
3. Its mirror pod must be visible in the API as `static-web-worker1`. Try
   deleting the mirror pod with kubectl and see what happens.

## Grading

```
lab check 18
```

## Cleaning up

After `lab check` passes:

```bash
kubectl delete namespace team-a
kubectl delete priorityclass critical-batch best-effort-batch
ssh worker1 sudo rm /etc/kubernetes/manifests/static-web.yaml   # the mirror pod disappears with it
rm -f ~/answers/18-static-path.txt
```

## Restarting this lab

```bash
lab start 18
```

This deletes namespace `team-a` and the static pod manifest on worker1 and recreates the starting objects, so you get the
original broken or empty state back. The PriorityClasses are cluster-wide; delete them too if you want to recreate them yourself:

```bash
kubectl delete priorityclass critical-batch best-effort-batch
```
