# Lab 21: NetworkPolicy

**Domain:** Services & Networking (20%)
**Curriculum:** Define and enforce Network Policies
**Suggested time:** 60 minutes · **Start with:** `lab start 21`

## Context

| Namespace (labels) | Pods (labels) |
|---|---|
| `frontend` (`tier=frontend`) | `web` (`app=web`), `other` (`app=other`) |
| `monitoring` (`purpose=monitoring`) | `web` (`app=web`), `prom` (`app=prom`) |
| `backend` (`tier=backend`) | `api` (`app=api`, HTTP on **80**), Service `api` |
| `db` (`tier=db`) | `postgres` (`app=db`, TCP **5432**), Service `postgres` |

Calico enforces NetworkPolicy. Everything is open right now.

## Tasks

1. **Default deny.** In `backend` and `db`, deny **all** ingress **and**
   egress for every pod, with one policy per namespace named `default-deny`.

2. **DNS.** Pods in `backend` and `db` may resolve names through **CoreDNS
   only** (UDP and TCP 53 to the CoreDNS pods), nothing else on port 53.

3. **Into api.** `backend/api` accepts TCP 80 **only** from pods labelled
   `app=web` **in namespaces labelled `tier=frontend`**. `frontend/other` and
   `monitoring/web` must be refused.

4. **api → db.** `backend/api` may connect to `db/postgres` on TCP 5432, and
   `postgres` accepts 5432 **only** from `backend/api`.

5. **Monitoring.** `monitoring/prom` (only that pod) may connect to
   `backend/api` on TCP 80.

6. **Out of the cluster.** `backend/api` may open SSH (TCP 22) to any machine
   in `10.10.10.0/24` **except** the jump host `10.10.10.10`.

Name policies as you like (except `default-deny`). Every rule above must hold
in **both** directions where both ends are restricted.

## Grading

```
lab check 21
```

The grader opens real connections between pods. Allowed paths must connect,
forbidden ones must time out.

## Notes

- Inside one `from:` entry, `namespaceSelector` and `podSelector` are ANDed.
  As two entries (two dashes), they're ORed. One dash is the whole lab.
- Egress policies select on **pod** IPs, not Service IPs. Connecting through a
  Service still works, because Calico evaluates the policy after the Service
  IP is translated to a pod IP.
- `kubernetes.io/metadata.name` is a label every namespace has automatically.
