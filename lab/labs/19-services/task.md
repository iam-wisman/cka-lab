# Lab 19: Services

**Domain:** Services & Networking (20%)
**Curriculum:** Use ClusterIP, NodePort, LoadBalancer service types and endpoints
**Suggested time:** 50 minutes · **Start with:** `lab start 19` · **Namespace:** `svc`

Deployment `api` (3 pods, label `app: api`) serves `api` over HTTP on a
container port **named `http`**. Pod `client` (busybox) is your test client.

## Tasks

1. **ClusterIP `api`**: port **8080**, targeting the container port **by
   name**, so the port number can change without editing the Service. A
   client must keep hitting the same pod for **10 minutes**.

2. **NodePort `api-public`**: node port **30080**. Responses must preserve the
   **client's source IP**, so nodes without an `api` pod must not forward
   traffic to other nodes. From `jump`, `curl http://<node-with-an-api-pod>:30080`
   answers `api`.

3. **Headless `api-peers`**: DNS returns every `api` pod IP, **including pods
   that aren't ready yet**.

4. **`legacy-dns`, a Service without a selector** that fronts the DNS server
   at `10.10.10.10` (outside the cluster) on port 53, **UDP and TCP**, port
   names `dns-udp` and `dns-tcp`. Wire it with an **EndpointSlice** you write
   yourself (not the legacy Endpoints API). From `client`,
   `nslookup db.corp.internal legacy-dns` must answer `10.10.10.30`.

5. **ExternalName `docs`** pointing to `kubernetes.io`.

## Grading

```
lab check 19
```

## Notes

- How does a Service find the EndpointSlices that belong to it? (One label.)
- `externalTrafficPolicy` has two values; one of them preserves source IPs.

## Cleaning up

After `lab check` passes:

```bash
kubectl delete namespace svc
```

## Restarting this lab

```bash
lab start 19
```

This deletes namespace `svc` and recreates the starting objects, so you get the
original broken or empty state back.
