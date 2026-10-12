# Lab 24: CoreDNS

**Domain:** Services & Networking (20%)
**Curriculum:** Understand and use CoreDNS
**Suggested time:** 45 minutes · **Start with:** `lab start 24` · **Namespace:** `dns`

## Context

Every pod resolves names through CoreDNS (Deployment and ConfigMap `coredns`
in `kube-system`). This cluster's domain is **`cka.local`** (lab 03), and the
jump host runs a DNS server for the company zone `corp.internal`.

## Tasks

1. **Stub domain.** Names under `corp.internal` are resolved by
   **`10.10.10.10`**; everything else keeps working as before.
   From pod `dns/probe`: `nslookup db.corp.internal` → `10.10.10.30`.

2. **Custom record.** `registry.cka.lab` resolves to `10.10.10.10` inside the
   cluster, without breaking resolution of any other name, including other
   `cka.lab` names such as `nfs.cka.lab`.

3. **Pod DNS config.** Pod **`dns-tuned`** in `dns` (`busybox:1.37`, `sleep infinity`):
   - it must **not** inherit the node's or the cluster's DNS settings
   - nameserver: the cluster DNS Service IP
   - search domains, in order: `dns.svc.cka.local`, `svc.cka.local`, `cka.local`
   - `ndots: 2`

4. **Answers.** Write `~/answers/24-dns.txt`:

   ```
   cluster_dns_ip=<ClusterIP of the cluster DNS Service>
   catalog_fqdn=<fully qualified name of Service dns/catalog>
   api_fqdn=<fully qualified name of the Kubernetes API Service>
   ```

5. **Survive restarts.** Your Corefile changes must be in the `coredns`
   ConfigMap, picked up **without** you restarting CoreDNS by hand (find
   what makes CoreDNS reload on its own), and CoreDNS must stay healthy.

## Grading

```
lab check 24
```

## Notes

- A Corefile can have several **server blocks**; the most specific zone wins.
- The `hosts` plugin answers only for names it knows **if** told to pass
  everything else on. Without that, it returns NXDOMAIN for the rest of its zone.
- `kubeadm upgrade` rewrites the CoreDNS ConfigMap only when it can migrate
  it safely; keep your edits minimal and valid.
