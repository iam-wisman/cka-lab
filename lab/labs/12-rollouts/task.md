# Lab 12: Rolling updates, failed releases, rollback and paused rollouts

**Domain:** Workloads & Scheduling (15%)
**Curriculum:** Understand application deployments and how to perform rolling update and rollbacks
**Suggested time:** 45 minutes · **Start with:** `lab start 12` · **Namespace:** `rollout`

Deployment `web` runs `nginx:1.26-alpine` with 4 replicas.

## Tasks

1. **Zero-downtime strategy.** Configure `web` so a rollout never drops below
   4 ready pods and may run up to 2 extra pods during the update. A new pod
   only counts as available after being ready for **5 seconds**. A rollout
   that makes no progress for **60 seconds** must be reported as failed. Keep
   only the last **4** old ReplicaSets.

2. **Release 1.27.** Update the image to `nginx:1.27-alpine`, with the
   change-cause `upgrade to 1.27` showing in `kubectl rollout history`.

3. **A bad release.** Update the image to `nginx:1.99-alpine` (it doesn't
   exist) with change-cause `bad release`. Confirm the Deployment reports that
   the rollout **failed**, and that all 4 old pods kept serving.
   Write that bad release's **revision number** to `~/answers/12-bad-revision.txt`.

4. **Roll back** to the 1.27 release using its revision number explicitly.

5. **One revision for two changes.** Make the following two changes so they
   produce **exactly one** new revision, with change-cause `tuning`:
   - container limits `cpu: 200m`, `memory: 128Mi` (requests `50m` / `64Mi`)
   - environment variable `RELEASE=blue`

   The Deployment must not be left paused.

## Grading

```
lab check 12
```

## Notes

- `kubectl rollout history deploy/web --revision=N` shows a revision's pod template.
- A rollback doesn't revert strategy settings; it only swaps the pod
  template back.
- `kubectl annotate ... kubernetes.io/change-cause=... --overwrite` sets the
  change-cause that history shows. (`--record` is gone.)
