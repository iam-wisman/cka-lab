#!/bin/bash
# Lab 06 setup: namespaces and objects the RBAC rules apply to.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: dev}
---
apiVersion: v1
kind: Namespace
metadata: {name: staging}
---
apiVersion: v1
kind: Namespace
metadata: {name: ci}
---
apiVersion: v1
kind: Secret
metadata: {name: db-credentials, namespace: dev}
stringData: {username: app, password: s3cr3t-do-not-read}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: dev}
spec:
  replicas: 1
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers: [{name: web, image: nginx:1.27-alpine}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: staging}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers: [{name: api, image: nginx:1.27-alpine}]
YAML
mkdir -p "$HOME/rbac"
