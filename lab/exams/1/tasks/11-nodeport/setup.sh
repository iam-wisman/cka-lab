#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t11 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t11 >/dev/null
kc apply -f - >/dev/null <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: e1-t11}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers: [{name: web, image: hashicorp/http-echo:1.0, args: ["-listen=:9090", "-text=web e1"], ports: [{name: http-alt, containerPort: 9090}]}]
Y
