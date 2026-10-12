#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t3 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t3 >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: {name: orders, namespace: e1-t3}
spec:
  replicas: 1
  selector: {matchLabels: {app: orders}}
  template:
    metadata: {labels: {app: orders}}
    spec:
      containers:
        - name: orders
          image: busybox:1.37
          command: [sh, -c, 'test "$DB_PASSWORD" = "S3cure!2026" && echo ready && sleep infinity']
          env:
            - name: DB_PASSWORD
              valueFrom: {secretKeyRef: {name: orders-db, key: password}}
YAML
kc -n e1-t3 get deploy orders -o jsonpath='{.metadata.generation}' >"$LAB_STATE/exam1-t3-gen"
