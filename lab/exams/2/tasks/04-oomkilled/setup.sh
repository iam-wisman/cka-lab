#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t4 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t4 >/dev/null
kc apply -f - >/dev/null <<'Y'
apiVersion: apps/v1
kind: Deployment
metadata: {name: etl, namespace: e2-t4}
spec:
  replicas: 1
  selector: {matchLabels: {app: etl}}
  template:
    metadata: {labels: {app: etl}}
    spec:
      containers:
        - name: etl
          image: python:3.13-alpine
          command: [python3, -c, "import time; b = b'x' * (120 * 1024 * 1024); print('batch loaded', flush=True); time.sleep(10**9)"]
          resources: {limits: {memory: 64Mi}}
Y
