# Lab 15: Probes, native sidecars and disruption budgets

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Understand the primitives used to create robust, self-healing, application deployments
**Suggested time:** 50 minutes · **Start with:** `lab start 15` · **Namespace:** `heal`

## Tasks

1. **slowapp is in a restart loop.** It needs about 40 seconds to warm up
   before it serves `/healthz` on port `8080`, and the liveness probe kills it
   first. Fix it **without** weakening the liveness probe (keep its path,
   port, period 5 s and failure threshold 3):
   - allow up to **90 seconds** for start-up, checked on `/healthz`
   - add a readiness probe on **`/ready`**, every **5 s**
   - after your fix, the pods reach `Ready` with **zero** restarts

2. **Disruption budget.** At most **one** `slowapp` pod may be voluntarily
   disrupted at a time. Name it `slowapp`.

3. **Native sidecar.** Deployment `logger` writes its log to a file nobody
   can read with `kubectl logs`. Add a sidecar container **`shipper`**
   (`busybox:1.37`) that streams `/var/log/app/app.log` to its stdout. It must
   be a **native sidecar**: started before the app container and kept running
   alongside it, declared where Kubernetes runs init containers.
   `kubectl logs deploy/logger -c shipper` shows the orders.

4. **A Job that finishes despite its sidecar.** Create Job **`report`**:
   - main container `report` (`busybox:1.37`) writes `report done` to
     `/out/report.txt` in a shared `emptyDir`, then exits 0 after 5 seconds
   - native sidecar `uploader` (`busybox:1.37`) runs `sleep infinity`
   - the Job must reach **Complete** (with a classic sidecar it never would)
   - no retries on failure; the Job object is deleted automatically **1 hour**
     after it finishes (so grade within the hour)

## Grading

```
lab check 15
```

## Notes

- A container with `restartPolicy: Always` inside `initContainers` is a
  native sidecar (GA since v1.33).
- startupProbe: Kubernetes waits `failureThreshold × periodSeconds` before
  giving up. Liveness and readiness probes don't run until it succeeds.

## Cleaning up

After `lab check` passes, run **`lab cleanup 15`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace heal
```

## Restarting this lab

```bash
lab start 15
```

This deletes namespace `heal` and recreates the starting objects, so you get the
original broken or empty state back.
