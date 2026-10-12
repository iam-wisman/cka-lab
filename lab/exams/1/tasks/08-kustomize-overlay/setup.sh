#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t8 --ignore-not-found --wait=true >/dev/null
B=$HOME/exam1/t8/base; rm -rf "$HOME/exam1/t8"; mkdir -p "$B"
cat >"$B/kustomization.yaml" <<'Y'
resources: [deployment.yaml]
Y
cat >"$B/deployment.yaml" <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec: {containers: [{name: api, image: nginx:1.27-alpine}]}
Y
