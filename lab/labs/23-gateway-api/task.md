# Lab 23: Gateway API with Envoy Gateway

**Domain:** Services & Networking (20%)
**Curriculum:** Use the Gateway API to manage Ingress traffic
**Suggested time:** 75 minutes · **Start with:** `lab start 23` · **Needs:** labs 10, 20

## Context

The Gateway API splits ingress into roles: the **infrastructure provider**
offers GatewayClasses, the **cluster operator** runs Gateways, and
**application teams** attach HTTPRoutes. You'll play all three, and keep a
team you don't trust (namespace `rogue`) from hijacking your hostname.

Namespace `store` (label `gateway-access=true`) runs Services `v1` and `v2`;
namespace `legacy` runs Service `legacy`. All answer with their own name on port 80.

## Tasks

1. **Controller.** Install **Envoy Gateway v1.9.2** with Helm from the OCI
   chart `oci://docker.io/envoyproxy/gateway-helm`, release `eg`, namespace
   **`envoy-gateway-system`**. It installs the Gateway API CRDs itself.
   Then run `lab start 23 rogue`.

2. **GatewayClass `eg`** for Envoy Gateway's controller, `Accepted`.

3. **Certificate `store-gw-tls`** in namespace **`infra`** for `store.cka.lab`, from ClusterIssuer `cka-ca`.

4. **Gateway `cka-gw`** in namespace **`infra`**, class `eg`:
   - listener **`http`**: HTTP, port 80, hostname `store.cka.lab`
   - listener **`https`**: HTTPS, port 443, hostname `store.cka.lab`,
     terminating TLS with `store-gw-tls`
   - both listeners accept routes **only from namespaces labelled
     `gateway-access=true`**
   - its Service gets **`10.10.10.202`** from MetalLB. Do it through the
     Gateway's own spec, not by editing generated objects.
   - `Programmed=True`

5. **HTTPRoute `store-redirect`** (namespace `store`), attached to the
   **`http` listener only**: everything gets a **301** to HTTPS.

6. **HTTPRoute `store`** (namespace `store`), attached to the **`https`
   listener only**, host `store.cka.lab`:
   - requests with header `x-canary: true` → **always** `v2`
   - `/old` and everything below → **301** to the same path with `/old`
     replaced by `/new`
   - `/legacy` → Service `legacy` in **namespace `legacy`**
   - everything else → `v1` **80 %**, `v2` **20 %**

7. The `rogue/admin` route must **not** be accepted by `cka-gw`.

## Grading

```
lab check 23
```

Test with `curl --cacert ~/cka-root-ca.crt --resolve store.cka.lab:443:10.10.10.202 https://store.cka.lab/...`

## Notes

- Route rules are matched by specificity, not by order. Header matches
  beat path-only matches with the same path.
- A route referencing a Service in another namespace needs that namespace's
  permission. What object grants it, and **where** does it live?
- `kubectl get gateway,httproute -A` and the `status.parents[].conditions` of
  a route tell you whether, and why, it was accepted.
- This cluster's DNS domain is **`cka.local`**, not `cluster.local`. Some
  software assumes the default. If a Gateway is `Accepted` but never
  `Programmed`, read the proxy's logs.
