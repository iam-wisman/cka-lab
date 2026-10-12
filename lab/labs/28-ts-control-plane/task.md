# Lab 28: Troubleshoot a degraded HA control plane

**Domain:** Troubleshooting (30%)
**Curriculum:** Troubleshoot cluster components · Manage and evaluate container output streams
**Suggested time:** 45 minutes · **Start with:** `lab start 28`

## Situation

Monitoring reports the control plane as degraded, yet `kubectl` works and
workloads still schedule. That's high availability hiding a problem.
Something is wrong on **each** of `cp1`, `cp2` and `cp3`.

## Tasks

1. Find every broken control-plane component and fix it, in place, in its
   static pod manifest. Don't regenerate manifests with kubeadm.
2. Afterwards all three API servers, controller managers and schedulers run
   with no more restarts, and the load balancer sees all three API servers UP.
3. Write what you found to `~/answers/28-faults.txt`, one line per node:

   ```
   cp1=<component>
   cp2=<component>
   cp3=<component>
   ```
   where `<component>` is one of `kube-apiserver`, `kube-controller-manager`,
   `kube-scheduler`, `etcd`.

## Grading

```
lab check 28
```

## Notes

- With one API server down, `kubectl logs` for **that** pod may still work
  (it goes through another API server), unless the kubelet on that node is
  involved. When it doesn't, `crictl ps -a` and `crictl logs` on the node do.
- The kubelet restarts static pods by itself after you save the manifest.
  Don't leave backup copies in `/etc/kubernetes/manifests/`: the kubelet runs
  **every** file there.

## Cleaning up

After `lab check` passes, run **`lab cleanup 28`**. It shows the commands below and asks before running them. Or run them by hand:

Nothing to remove. Make sure no backup copies of manifests were left in the
manifests directory: the kubelet would run them as extra pods.

```bash
for n in cp1 cp2 cp3; do ssh $n ls /etc/kubernetes/manifests/; done   # exactly 4 files each
rm -f ~/answers/28-faults.txt
```

## Restarting this lab

```bash
lab start 28
```

This breaks one component on each control plane again, the same way.
