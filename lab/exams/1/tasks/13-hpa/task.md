## Task 13 (5 %) · Workloads & Scheduling

### Autoscale on CPU

Create a HorizontalPodAutoscaler **`worker`** for Deployment `worker` in
namespace `e1-t13`: **2–6** replicas, target **65 %** average CPU utilization.
The HPA must be able to read metrics (no `<unknown>`). Containers should
request `50m` CPU.
