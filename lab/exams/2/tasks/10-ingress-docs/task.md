## Task 10 (7 %) · Services & Networking

### Publish the docs site

Publish Service `docs` (namespace `e2-t10`, port 80) at
**`https://docs.cka.lab/`** through the **traefik** IngressClass (lab 22),
with a certificate from ClusterIssuer `cka-ca` in Secret `docs-tls`. Use an
Ingress named **`docs`**.
