#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace rollout --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: rollout}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: rollout
  annotations: {kubernetes.io/change-cause: "initial release 1.26"}
spec:
  replicas: 4
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - name: web
          image: nginx:1.26-alpine
          readinessProbe: {httpGet: {path: /, port: 80}, periodSeconds: 2}
YAML
kc -n rollout rollout status deploy/web --timeout=180s >/dev/null
mkdir -p "$HOME/answers"
