# Lab 30: Troubleshoot Services, DNS and policy

**Domain:** Troubleshooting (30%)
**Curriculum:** Troubleshoot services and networking
**Suggested time:** 50 minutes · **Start with:** `lab start 30` · **Namespace:** `ts-net`

## Situation

From pod **`shopper`**, none of these work, and each fails for its own reason:

```
kubectl -n ts-net exec shopper -- wget -qO- -T 3 http://checkout
kubectl -n ts-net exec shopper -- wget -qO- -T 3 http://payments
kubectl -n ts-net exec shopper -- wget -qO- -T 3 http://inventory
```

There are **five** faults in total, one of them cluster-wide.

## Tasks

Make all three answer (`checkout ok`, `payments ok`, `inventory ok`) from
`shopper` **by Service name**, with these constraints:

- don't change any Deployment or its pods' labels; fix the Services
- keep NetworkPolicy `lockdown` as it is; allow **only `shopper`** into
  `inventory`, on its port, in a new policy
- `shopper` must use cluster DNS, the way normal pods do
- every pod in the cluster must resolve `<service>.<namespace>.svc.cka.local`
  again

## Grading

```
lab check 30
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
- [Network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [DNS for Services and Pods (dnsPolicy)](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 30`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace ts-net
```

**Keep:** The CoreDNS fix (zone `cka.local`): every name in the cluster depends on it.

## Restarting this lab

```bash
lab start 30
```

This deletes namespace `ts-net` and breaks the CoreDNS zone again and recreates the starting objects, so you get the
original broken or empty state back.
