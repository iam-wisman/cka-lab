# Lab 20: LoadBalancer Services on bare metal with MetalLB (L2)

**Domain:** Services & Networking (20%)
**Curriculum:** Use ClusterIP, NodePort, LoadBalancer service types and endpoints
**Suggested time:** 40 minutes · **Start with:** `lab start 20`

## Context

On a cloud, `type: LoadBalancer` gets an address from the provider. On bare
metal nothing assigns one, and `EXTERNAL-IP` stays `<pending>` forever.
MetalLB fills that gap: it allocates addresses from pools you define and
answers ARP for them on the lab network.

## Tasks

1. Install MetalLB with Helm: chart **`metallb` 0.16.1** from
   `https://metallb.github.io/metallb`, release `metallb`, namespace
   **`metallb-system`**. The namespace must allow MetalLB's speaker to run
   with the privileges it needs under Pod Security admission.

2. Two address pools, both announced in **L2** mode:
   - **`lab-pool`**: `10.10.10.200`–`10.10.10.220`, handed out automatically
   - **`reserved`**: `10.10.10.230`–`10.10.10.235`, used **only** when a
     Service explicitly asks for it

3. In namespace `lb` (Deployment `web` exists, port 5678):
   - Service **`web`**, type LoadBalancer, port 80, **exactly `10.10.10.205`**
   - Service **`web-reserved`**, type LoadBalancer, port 80, any address
     from the `reserved` pool
   - `curl http://10.10.10.205` from `jump` answers `hello from lb`

4. Prove auto-assignment skips `reserved`: Service **`web-auto`**
   (LoadBalancer, port 80, no annotations) gets an address from `lab-pool`.

## Grading

```
lab check 20
```

## Notes

- Addresses 10.10.10.201–203 will be used by labs 22/23; don't pin them here.
- MetalLB's custom resources live in `metallb.io/v1beta1`.

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Service type LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
- [Pod Security admission (namespace labels)](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [MetalLB: installation](https://metallb.io/installation/)
- [MetalLB: configuration](https://metallb.io/configuration/)
- [MetalLB: usage (annotations)](https://metallb.io/usage/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 20`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace lb          # releases 10.10.10.205 and the other addresses
```

**Keep:** MetalLB, its pools and the L2Advertisement: Traefik (lab 22) and the Gateway (lab 23) get their addresses from it.

## Restarting this lab

```bash
lab start 20
```

This deletes namespace `lb` and recreates the starting objects, so you get the
original broken or empty state back.

To redo the MetalLB **installation** as well (Traefik and the Gateway lose
their addresses until you reinstall):

```bash
helm uninstall metallb -n metallb-system
kubectl delete namespace metallb-system
```
