# CKA mock exam 2

**Time:** 120 minutes · **Tasks:** 16 · **Pass mark:** 66 % · Kubernetes v1.35

Before you start, save the cluster: `lab snapshot before-exam2`. Some tasks
break things on purpose; afterwards `lab reset before-exam2` gets you back.

Rules, like the real exam:
- Work from `jump`. Each task names the node or namespace to use, and has its own
  kubeconfig context (`e2-t3` for task 3, default namespace `e2-t3`): switch first
  with `kubectl config use-context`, as in the real exam.
- Use only the documentation the real exam allows: mainly kubernetes.io/docs (see the Linux Foundation candidate handbook for the current list).
- Answers that go into files go under `/home/student/exam2/`.
- Partial credit: each task is graded check by check and weighted.
- Move on when stuck. A 4 % task isn't worth 15 minutes.

`lab exam 2 status` shows the time left. `lab exam 2 check` grades everything.

## Cleaning up

**Recommended:** `lab reset before-exam2`. Some tasks break worker1's kubelet and
cp3's API server, and a reset undoes whatever you didn't fix.

Otherwise, after fixing tasks 1 and 2, run **`lab exam 2 cleanup`**, which runs these commands:

```bash
kubectl delete namespace e2-t3 e2-t4 e2-t5 e2-t7 e2-t8 e2-t10 e2-t11 e2-t12 e2-t13 e2-t14 e2-t15 e2-t16
kubectl delete crd databaseclaims.data.cka.lab
kubectl delete pv e2-data --ignore-not-found
kubectl delete csr eve --ignore-not-found
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" and (.spec.claimRef.namespace | startswith("e2-"))) | .metadata.name' | xargs -r kubectl delete pv
ssh nfs 'sudo rm -rf /srv/nfs/k8s/e2-*'
ssh worker1 'sudo rm -rf /mnt/e2-data'
ssh cp1 "sudo kubeadm token list | awk '/exam2 worker/ {print \$1}' | xargs -r -n1 sudo kubeadm token delete"
rm -rf ~/exam2
```

The `vault.cka.lab` entry you added to CoreDNS is harmless. Remove it from the
`coredns` ConfigMap if you want.

## Restarting the exam

```bash
lab reset before-exam2      # back to the clean cluster
lab exam 2 start            # sets every task up again and restarts the 120-minute timer
```

`lab exam 2 start` refuses while a previous attempt's timer is still running.
To abandon an attempt early: `rm -rf ~/.cka-lab/exam-2`.
