#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace shop --ignore-not-found --wait=true >/dev/null
kc create namespace shop >/dev/null
for app in api static fallback; do
  kc apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $app, namespace: shop}
spec:
  replicas: 1
  selector: {matchLabels: {app: $app}}
  template:
    metadata: {labels: {app: $app}}
    spec:
      containers:
        - {name: $app, image: hashicorp/http-echo:1.0, args: ["-listen=:5678", "-text=$app"], ports: [{containerPort: 5678}]}
---
apiVersion: v1
kind: Service
metadata: {name: $app, namespace: shop}
spec: {selector: {app: $app}, ports: [{port: 80, targetPort: 5678}]}
YAML
done
