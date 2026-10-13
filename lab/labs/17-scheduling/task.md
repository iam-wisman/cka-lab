# Lab 17: Affinity, anti-affinity, topology spread, taints and manual scheduling

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Configure Pod admission and scheduling (limits, node affinity, etc.)
**Suggested time:** 60 minutes · **Start with:** `lab start 17` · **Namespace:** `sched`

`lab start 17` tainted `worker2` with `dedicated=analytics:NoSchedule`.
Zones (lab 05): cp1/worker1 = `zone-a`, cp2/worker2 = `zone-b`, cp3 = `zone-c`.

## Tasks

1. **analytics** Deployment, 2 replicas (`busybox:1.37`, `sleep infinity`,
   label `app: analytics`): must run **only** on `worker2`, the dedicated node.
   Tolerating the taint isn't enough on its own. Think about why.

2. **edge** Deployment, **6** replicas (`nginx:1.27-alpine`, label `app: edge`):
   - spread **exactly evenly** over the three zones (2 per zone); a pod that
     would break the balance must stay `Pending` rather than be placed
   - may run on control-plane nodes, but **never** on the dedicated analytics node
   - within a zone, prefer different nodes

3. **fast-io** Pod (`busybox:1.37`, `sleep infinity`):
   - **must** run in `zone-a` or `zone-b`
   - **prefers** (weight 80) nodes labelled `disktype=ssd`
   - label `worker1` with `disktype=ssd`; fast-io must end up there

4. **cache** Deployment, 2 replicas (`redis:7-alpine`, label `app: cache`):
   no two cache pods on the same node, and each cache pod on the **same node**
   as an `edge` pod.

5. **manual** Pod (`nginx:1.27-alpine`): put it on **cp3** **without** the
   scheduler. It must be `Running`.

## Grading

```
lab check 17
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Assigning Pods to Nodes (affinity, nodeName)](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Pod topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 17`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace sched
kubectl taint node worker2 dedicated-              # the lab's dedicated-node taint
kubectl label node worker1 disktype-
```

Leaving the taint makes later labs squeeze onto worker1. (Lab 18's setup
removes it too, in case you forget.)

## Restarting this lab

```bash
lab start 17
```

This deletes namespace `sched`, removes `disktype` from worker1 and re-taints worker2 and recreates the starting objects, so you get the
original broken or empty state back.
