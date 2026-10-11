#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace scale --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: scale}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: scale}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: api
          image: registry.k8s.io/hpa-example
          ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: scale}
spec:
  selector: {app: api}
  ports: [{port: 80}]
YAML
