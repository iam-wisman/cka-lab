## Task 11 (6 %) · Services & Networking

### Restrict outbound traffic

In namespace `e2-t11`, pod `client` (`app=client`) may only open connections
to Service `api` in the same namespace (TCP 80) and look up names through
cluster DNS. Everything else it tries to reach outward must be blocked.
Name the policy **`client-egress`**.
