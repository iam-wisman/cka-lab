# Lab 14: HPA v2 with behavior, and in-place pod resize

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Configure workload autoscaling
**Suggested time:** 50 minutes · **Start with:** `lab start 14` · **Namespace:** `scale`
**Needs:** metrics-server from lab 09

## Part A: HorizontalPodAutoscaler

Deployment `api` (a CPU-hungry PHP app) and Service `api` exist.

1. Create an `autoscaling/v2` HPA named **`api`** for Deployment `api`:
   - between **2** and **8** replicas
   - target **50 %** average CPU utilization **and** an average memory usage of **100Mi** per pod
   - **scale-up:** at most double the replicas every 15 seconds
   - **scale-down:** wait for **120 s** of stable recommendations, then remove
     at most **1 pod per minute**
2. The HPA must actually work: `kubectl get hpa` shows real numbers for both
   metrics (no `<unknown>`), and the autoscaler reports it can compute a
   replica count. Fix whatever stops it. The containers should request
   `100m` CPU and `64Mi` memory.
3. Optional (not graded): generate load and watch it scale:
   `kubectl run load --rm -it --image=busybox:1.37 -n scale -- sh -c 'while true; do wget -qO- http://api; done'`

## Part B: in-place pod resize (GA in v1.35)

1. Create Pod **`resizer`** (image `nginx:1.27-alpine`) with
   requests `cpu: 100m, memory: 64Mi` and limits `cpu: 200m, memory: 128Mi`,
   configured so that **changing CPU never restarts the container** but
   **changing memory restarts it**.
2. Then resize the running pod, **without recreating it**, to:
   - CPU request `250m`, limit `500m`
   - memory limit `192Mi` (request unchanged)
3. When you're done, the container has been restarted **exactly once**, and
   the kubelet reports the new resources as applied.

## Grading

```
lab check 14
```

## Notes

- `kubectl describe hpa` explains why metrics are missing.
- Resizing uses a dedicated subresource. Editing the pod spec the normal way is rejected.

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Horizontal Pod Autoscaling (incl. behavior)](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/)
- [HorizontalPodAutoscaler walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Resize CPU and memory resources assigned to containers](https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 14`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace scale
```

## Restarting this lab

```bash
lab start 14
```

This deletes namespace `scale` and recreates the starting objects, so you get the
original broken or empty state back.
