## Task 5 (7 %) · Cluster Architecture

### A user for the ops team

Issue a client certificate for user **`eve`** in group **`ops`** through the
Kubernetes CSR API (CSR name `eve`), and build `/home/student/exam2/eve.kubeconfig`
(certificate data embedded, server `https://k8s-api.cka.lab:6443`). In namespace
`e2-t5`, `eve` may **get, list and watch Deployments**, and nothing else.
