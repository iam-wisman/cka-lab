# Lab 07: Upgrade the HA cluster from v1.34 to v1.35 without downtime

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Manage the lifecycle of Kubernetes clusters
**Suggested time:** 90 minutes · **Start with:** `lab start 07`

## Context

The cluster runs v1.34.12. Upgrade it to **v1.35.9**, the version the CKA
exam targets, the way you would in production: one node at a time, control
planes first, while the `uptime` namespace keeps serving.

`lab start 07` deploys the `uptime` workloads. One of them has a
PodDisruptionBudget the application team insists on. **You may not modify or
delete it.**

## Tasks

1. **Packages.** On all five nodes: kubeadm, kubelet and kubectl at exactly
   **1.35.9**, from the pkgs.k8s.io **v1.35** channel, held again afterwards.
   Same for kubectl on `jump`.

2. **Control plane.** Upgrade the control-plane nodes **one at a time**: the
   first with the kubeadm command that upgrades the cluster, the other two with
   the one that upgrades a node. Every static control-plane component, the
   cluster configuration kubeadm stores, CoreDNS and kube-proxy must end up at
   the versions kubeadm v1.35.9 chooses.

3. **Workers and kubelets.** Before upgrading each node's kubelet, move its
   workloads off it safely, then bring it back into service. When you're done,
   no node may be left unschedulable.

4. **Runtime consistency.** If kubeadm v1.35.9 expects a different pause
   image than v1.34.12, update containerd's pinned sandbox image on every node
   (lab 01) to match.

5. **The workload survives.**
   - PodDisruptionBudget `uptime/frontend` is the **same object** with the
     **same spec** as `lab start 07` created it
   - Deployment `uptime/frontend` ends with **4 replicas, all available**
   - DaemonSet `uptime/node-agent` and Deployment `uptime/cache` are fully
     available on the upgraded nodes

6. **Snapshot** (optional but recommended): `lab snapshot upgraded`.

## Grading

```
lab check 07
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [Changing the Kubernetes package repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)
- [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
- [Disruptions and PodDisruptionBudgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Version skew policy](https://kubernetes.io/releases/version-skew-policy/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 07`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace uptime
```

**Keep:** The upgrade itself: all later labs and the mock exams assume v1.35.9.

## Restarting this lab

This lab changes the nodes themselves, so the only clean restart is a
snapshot. Take one **before** you start:

```bash
lab snapshot before-07
# ... attempt the lab ...
lab reset before-07        # the cluster and the lab files on jump roll back; grades are kept
```

If you didn't take one, there is no supported downgrade: `lab reset cluster-ready` (from lab 05) is the way back to v1.34.12.
