#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
drill_ns "$NS"
kc -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  replicas: 1
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - {name: api, image: hashicorp/http-echo:1.0, args: ["-listen=:$APORT", "-text=ok"]}
---
apiVersion: v1
kind: Pod
metadata: {name: $GOOD, labels: {role: $ROLE}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Pod
metadata: {name: intruder, labels: {role: guest}}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
YAML
kc -n "$NS" rollout status deploy/api --timeout=180s >/dev/null
kc -n "$NS" wait --for=condition=Ready pod --all --timeout=120s >/dev/null
