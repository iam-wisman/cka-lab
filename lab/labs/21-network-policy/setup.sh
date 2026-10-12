#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
for ns in frontend backend db monitoring; do kc delete namespace $ns --ignore-not-found --wait=true >/dev/null; done
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: frontend, labels: {tier: frontend}}
---
apiVersion: v1
kind: Namespace
metadata: {name: backend, labels: {tier: backend}}
---
apiVersion: v1
kind: Namespace
metadata: {name: db, labels: {tier: db}}
---
apiVersion: v1
kind: Namespace
metadata: {name: monitoring, labels: {purpose: monitoring}}
---
apiVersion: v1
kind: Pod
metadata: {name: web, namespace: frontend, labels: {app: web}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Pod
metadata: {name: other, namespace: frontend, labels: {app: other}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Pod
metadata: {name: web, namespace: monitoring, labels: {app: web}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Pod
metadata: {name: prom, namespace: monitoring, labels: {app: prom}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Pod
metadata: {name: api, namespace: backend, labels: {app: api}}
spec:
  containers:
    - name: api
      image: nginx:1.27-alpine
      ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: backend}
spec: {selector: {app: api}, ports: [{port: 80}]}
---
apiVersion: v1
kind: Pod
metadata: {name: postgres, namespace: db, labels: {app: db}}
spec:
  containers:
    - name: db
      image: nginx:1.27-alpine
      command: [sh, -c, "sed -i 's/listen  *80;/listen 5432;/' /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"]
      ports: [{containerPort: 5432}]
---
apiVersion: v1
kind: Service
metadata: {name: postgres, namespace: db}
spec: {selector: {app: db}, ports: [{port: 5432}]}
YAML
for ns in frontend backend db monitoring; do kc -n $ns wait --for=condition=Ready pod --all --timeout=180s >/dev/null; done
