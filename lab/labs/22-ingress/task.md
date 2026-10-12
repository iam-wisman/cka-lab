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

2. **Ingress `shop`** in namespace `shop`, class `traefik`, host
   **`shop.cka.lab`**:
   - `/api` and everything under it → `api`
   - exactly `/static` (nothing below it) → `static`
   - any request the rules don't match → `fallback`
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

## Notes

- `pathType: Prefix` matches on path *elements*: `/api` matches `/api/x`
  but not `/apiv2`.
- An Ingress with no `ingressClassName` is picked up only by the default class.
- Read `helm show values traefik/traefik --version 41.7.1` for `ingressClass`,
  `providers`, `service` and `ports`.
