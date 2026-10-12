#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t3 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t3 >/dev/null
kc apply -f - >/dev/null <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: {name: catalog, namespace: e2-t3}
spec:
  replicas: 2
  selector: {matchLabels: {app: catalog}}
  template:
    metadata: {labels: {app: catalog, version: v2}}
    spec: {containers: [{name: c, image: hashicorp/http-echo:1.0, args: ["-listen=:5678", "-text=catalog v2"], ports: [{containerPort: 5678}]}]}
---
apiVersion: v1
kind: Service
metadata: {name: catalog, namespace: e2-t3}
spec: {selector: {app: catalog, version: v1}, ports: [{port: 80, targetPort: 8080}]}
Y
