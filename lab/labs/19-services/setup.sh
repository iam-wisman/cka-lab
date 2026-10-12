#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace svc --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: svc}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: svc}
spec:
  replicas: 3
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api, tier: backend}}
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args: ["-listen=:5678", "-text=api"]
          ports: [{name: http, containerPort: 5678}]
---
apiVersion: v1
kind: Pod
metadata: {name: client, namespace: svc, labels: {app: client}}
spec:
  containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]
YAML
kc -n svc rollout status deploy/api --timeout=180s >/dev/null
kc -n svc wait --for=condition=Ready pod/client --timeout=120s >/dev/null
