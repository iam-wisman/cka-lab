# Lab 22: Ingress with Traefik

**Domain:** Services & Networking (20%)
**Curriculum:** Know how to use Ingress controllers and Ingress resources
**Suggested time:** 55 minutes · **Start with:** `lab start 22` · **Needs:** labs 10 (cert-manager CA) and 20 (MetalLB)

## Context

An Ingress resource does nothing without a controller. The community
ingress-nginx project was retired in March 2026; this lab uses **Traefik**.
Namespace `shop` has Services `api`, `static` and `fallback`, each answering
its own name over HTTP.

## Tasks

1. **Controller.** Install the **`traefik`** Helm chart **41.7.1**
   (`https://traefik.github.io/charts`) as release `traefik` in namespace
   **`traefik`**, from `~/helm/traefik.yaml`:
   - 2 replicas
   - IngressClass **`traefik`**, **not** the cluster default
   - its LoadBalancer Service gets **`10.10.10.201`** from MetalLB
   - it watches Ingress resources only (its Gateway API provider stays **off**;
     lab 23 uses a different controller)
   - plain HTTP on port 80 redirects **permanently** to HTTPS
   - `pathType: Prefix` must match **whole path elements**, as the Ingress
     specification defines it (`/api` matches `/api/x`, never `/apiv2`).
     Traefik does not do this by default.

2. **Ingress `shop`** in namespace `shop`, class `traefik`, host
   **`shop.cka.lab`**:
   - `/api` and everything under it → `api`
   - exactly `/static` (nothing below it) → `static`
   - every other path on `shop.cka.lab` → `fallback`, with an explicit
     catch-all rule (test it over HTTPS: controllers differ in how they serve
     an Ingress-level `defaultBackend`, and in how they **order** rules)
   - TLS for `shop.cka.lab` with a certificate **issued automatically by
     cert-manager** from ClusterIssuer `cka-ca` into Secret `shop-tls`. Use the
     Ingress itself to ask for it; don't write a Certificate object.

3. From `jump`, with the CKA root CA trusted (export it from
   `cert-manager/cka-root-ca` to `~/cka-root-ca.crt`), these must work **without** `-k`:

   ```
   curl --cacert ~/cka-root-ca.crt --resolve shop.cka.lab:443:10.10.10.201 https://shop.cka.lab/api/orders   # api
   curl --cacert ~/cka-root-ca.crt --resolve shop.cka.lab:443:10.10.10.201 https://shop.cka.lab/static       # static
   curl --cacert ~/cka-root-ca.crt --resolve shop.cka.lab:443:10.10.10.201 https://shop.cka.lab/static/x     # fallback
   ```

## Grading

```
lab check 22
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Ingress (path types, default backend, TLS)](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [Traefik: Kubernetes Ingress](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [cert-manager: securing Ingress resources](https://cert-manager.io/docs/usage/ingress/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 22`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace shop
```

**Keep:** The Traefik release (mock exam 2 publishes through it) and `~/cka-root-ca.crt`.

## Restarting this lab

```bash
lab start 22
```

This deletes namespace `shop` and recreates the starting objects, so you get the
original broken or empty state back.

To redo the Traefik **installation** too:

```bash
helm uninstall traefik -n traefik
kubectl delete namespace traefik
```
