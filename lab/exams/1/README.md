# CKA mock exam 1

**Time:** 120 minutes · **Tasks:** 16 · **Pass mark:** 66 % · Kubernetes v1.35

Before you start, save the cluster: `lab snapshot before-exam1`. Some tasks
break things on purpose; afterwards `lab reset before-exam1` gets you back.

Rules, like the real exam:
- Work from `jump`. Each task names the node or namespace to use.
- kubernetes.io/docs, the Helm docs and the Gateway API docs are allowed; nothing else.
- Answers that go into files go under `/home/student/exam1/`.
- Partial credit: each task is graded check by check and weighted.
- Move on when stuck. A 4 % task isn't worth 15 minutes.

`lab exam 1 status` shows the time left. `lab exam 1 check` grades everything.

## Cleaning up

**Recommended:** `lab reset before-exam1`. Some tasks break worker2's kubelet and
cp1's scheduler, and a reset undoes whatever you didn't fix.

Otherwise, after fixing tasks 1 and 2, run **`lab exam 1 cleanup`**, which runs these commands:

```bash
kubectl delete namespace e1-t2 e1-t3 e1-t4 e1-t5 e1-apps e1-t7 e1-t8 e1-t9 e1-t10 e1-t11 e1-t12 e1-t13 e1-t14 e1-t15
kubectl delete clusterrole pod-reader-e1
kubectl delete storageclass exam-retain
kubectl taint node worker2 reserved-
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" and (.spec.claimRef.namespace | startswith("e1-"))) | .metadata.name' | xargs -r kubectl delete pv
ssh nfs 'sudo rm -rf /srv/nfs/k8s/e1-*'
ssh cp1 'sudo rm -f /var/backups/etcd/exam1.*'
rm -rf ~/exam1
```

## Restarting the exam

```bash
lab reset before-exam1      # back to the clean cluster
lab exam 1 start            # sets every task up again and restarts the 120-minute timer
```

`lab exam 1 start` refuses while a previous attempt's timer is still running.
To abandon an attempt early: `rm -rf ~/.cka-lab/exam-1`.
