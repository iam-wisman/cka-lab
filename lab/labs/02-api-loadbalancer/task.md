# Lab 02: Load-balance the API server for an HA control plane

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Implement and configure a highly-available control plane
**Suggested time:** 40 minutes · **Work on:** `jump`

## Context

The cluster will have three control-plane nodes. Clients (kubelets, kubectl,
controllers) must reach "the API server" through one stable address that keeps
working when any one control plane is down. kubeadm calls this the
`controlPlaneEndpoint`.

The DNS name `k8s-api.cka.lab` already resolves to `10.10.10.10`, the jump
host's lab-network address. Make that address a TCP load balancer for the
three API servers. The API servers don't exist yet; you are building the front
door first, the way kubeadm's HA guide does.

## Tasks

1. Install **HAProxy** on `jump` from the Ubuntu archive. It must be enabled
   and running.

2. Configure a frontend that listens on **10.10.10.10:6443 only**: not on the
   LAN-side address, not on `0.0.0.0`. Traffic is TLS that HAProxy must **not**
   terminate.

3. Send it to a backend of `cp1`, `cp2` and `cp3` on port 6443, by IP address,
   with the server names `cp1`, `cp2` and `cp3`. Use round-robin balancing.

4. **Health checks.** A TCP connect isn't enough: an API server can accept
   connections while it isn't ready. Health-check each server with an HTTPS
   `GET /readyz` that expects status **200**, without verifying the certificate.
   Check every 3 seconds; mark a server down after 3 failures and up after 2
   successes. When a server is marked down, **close its existing
   connections**: kubelets and controllers hold one long-lived connection, and
   by default HAProxy leaves it pinned to the dead server.

5. **Long-lived connections.** `kubectl get -w`, `kubectl logs -f` and every
   controller's watch must not be cut off after HAProxy's default 50 seconds of
   inactivity. Set the client and server timeouts to **at least 1 hour**.

6. **Stats page** on `10.10.10.10:8404` (that address only) at URI `/stats`, so you can see
   which API servers are up. The CSV form (`/stats;csv`) must be reachable from
   `jump` without authentication.

7. The configuration must pass `haproxy -c` with no warnings or alerts.

Right now all three backends will show **DOWN**. That's correct until lab 03.

## Grading

```
lab check 02
```

## Notes

- Because HAProxy runs in TCP mode, the HTTP health check is separate from the
  traffic: look at `option httpchk`, `http-check`, and the `check-ssl` and
  `verify` server options.
- In production you'd run two load balancers with a floating VIP (keepalived)
  so the load balancer isn't a single point of failure. kubeadm's "Options for
  Software Load Balancing" document covers it; read it.
