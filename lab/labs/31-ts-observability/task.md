# Lab 31: Metrics, previous logs, stdout vs stderr, and the kubelet's own log

**Domain:** Troubleshooting (30%)
**Curriculum:** Monitor cluster and application resource usage · Manage and
evaluate container output streams · Troubleshoot cluster components
**Suggested time:** 45 minutes · **Start with:** `lab start 31` · **Namespace:** `ts-obs`
**Needs:** metrics-server (lab 09)

Write every answer to the file named, on `jump`.

## Tasks

1. **CPU.** The pod in `ts-obs` using the **most CPU** right now →
   `~/answers/31-top-pod.txt` (just the pod name). Give metrics a minute to settle.

2. **The crash nobody saw.** Pod `flaky` keeps restarting. Copy the exact
   **error line** its container printed **just before it died** to
   `~/answers/31-flaky.txt`.

3. **Streams.** Pod `mixed` writes informational lines to stdout and errors
   to stderr. Collect **only its stderr lines** (the messages, without
   timestamps or stream markers), at least 5 of them, into
   `~/answers/31-stderr.txt`. `kubectl logs` merges the two streams; find where
   the node keeps them apart.

4. **Which container?** Pod `multi` has two containers. One printed an
   `AUDIT-TOKEN=...` line when it started. Put that whole line in
   `~/answers/31-token.txt`.

5. **The kubelet is unhappy.** One node's kubelet keeps logging an error about
   a file it can't use. Find it from the **kubelet's log** on that node,
   write the file's absolute path to `~/answers/31-badfile.txt`, and remove
   the file so the error stops.

## Grading

```
lab check 31
```

## Cleaning up

After `lab check` passes, run **`lab cleanup 31`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace ts-obs
rm -f ~/answers/31-*.txt
```

## Restarting this lab

```bash
lab start 31
```

This deletes namespace `ts-obs` and puts the broken manifest back on worker1 and recreates the starting objects, so you get the
original broken or empty state back.
