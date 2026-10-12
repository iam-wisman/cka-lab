# Lab 16: DaemonSets, StatefulSets, indexed Jobs and CronJobs

**Domain:** Workloads & Scheduling (15%)
**Suggested time:** 50 minutes · **Start with:** `lab start 16` · **Namespace:** `batch`

## Tasks

1. **DaemonSet `node-agent`** (`busybox:1.37`, `sleep infinity`) on **all
   five nodes**, control planes included. During updates, at most **2** nodes'
   agents may be down at once. Pods carry label `app: node-agent`.

2. **StatefulSet `kv`** with **3** replicas (`nginx:1.27-alpine`, port 80,
   label `app: kv`), governed by a **headless** Service `kv`. All three pods
   must start **in parallel**, not one after another. From any pod in the
   cluster, `kv-1` must be reachable at its stable DNS name. Write that fully
   qualified name to `~/answers/16-kv1-fqdn.txt`.
   (Remember the cluster domain from lab 03.)

3. **Indexed Job `shards`**: **6** completions, **2** at a time, each pod
   prints `processing shard <index>` (its completion index, 0–5) and exits.
   At most **1** retry per index (not for the Job as a whole), and the Job
   must fail if it runs longer than **120** seconds.

4. **CronJob `cleanup`** (`busybox:1.37`, `echo cleaned`):
   - every **5 minutes**, in the **`America/New_York`** time zone
   - never two runs at the same time
   - a run that can't start within **60 s** of its schedule is skipped
   - keep **2** successful and **1** failed Job in history

   Then start a run **now**, by hand, from the CronJob's template, as Job
   **`cleanup-manual`**.

## Grading

```
lab check 16
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Jobs (incl. indexed completion, backoffLimitPerIndex)](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob (incl. time zones)](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 16`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace batch
rm -f ~/answers/16-kv1-fqdn.txt
```

## Restarting this lab

```bash
lab start 16
```

This deletes namespace `batch` and recreates the starting objects, so you get the
original broken or empty state back.
