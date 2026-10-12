#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace lb --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: lb}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: lb}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - {name: web, image: hashicorp/http-echo:1.0, args: ["-listen=:5678", "-text=hello from lb"], ports: [{containerPort: 5678}]}
YAML
