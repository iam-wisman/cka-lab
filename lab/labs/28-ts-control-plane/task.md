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

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Troubleshooting clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [kube-apiserver reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)
- [kube-scheduler reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/)
- [kube-controller-manager reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)
- [Leases (leader election)](https://kubernetes.io/docs/concepts/architecture/leases/)
- [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/)

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
