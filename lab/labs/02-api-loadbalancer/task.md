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

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Creating highly available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [kubeadm HA considerations: software load balancing](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md)
- [Kubernetes API health endpoints (/readyz)](https://kubernetes.io/docs/reference/using-api/health-checks/)
- [HAProxy documentation](https://docs.haproxy.org/)

## Cleaning up

`lab cleanup 02` has nothing to remove here.

Nothing to remove: what you built here **is** the cluster every later lab
uses. Take a snapshot instead so you can come back to this point:

```bash
lab snapshot after-02
```

**Keep:** HAProxy on jump: every later lab reaches the API through it.

## Restarting this lab

HAProxy only lives on jump, so you can redo this lab without touching the nodes:

```bash
sudo systemctl disable --now haproxy
sudo apt-get purge -y haproxy && sudo rm -rf /etc/haproxy
```
