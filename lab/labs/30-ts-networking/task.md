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

## Notes

- Work outward from the client: name resolution → Service → EndpointSlices → pod port → policy.
- `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` is the
  fastest way to see whether a Service found any pods.
