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

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Customizing DNS service (CoreDNS)](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)
- [DNS for Services and Pods (dnsPolicy, dnsConfig)](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
- [CoreDNS plugin: hosts](https://coredns.io/plugins/hosts/)
- [CoreDNS plugin: forward](https://coredns.io/plugins/forward/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 24`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace dns
rm -f ~/answers/24-dns.txt
```

The Corefile changes (the `corp.internal` stub and the `registry.cka.lab`
hosts entry) are harmless to keep. To remove them, edit the `coredns`
ConfigMap; the `reload` plugin applies it within a minute or two.

## Restarting this lab

```bash
lab start 24
```

This deletes namespace `dns` and recreates the starting objects, so you get the
original broken or empty state back.

Your Corefile edits stay. To redo them, take them out of the `coredns`
ConfigMap first (`kubectl -n kube-system edit cm coredns`).
