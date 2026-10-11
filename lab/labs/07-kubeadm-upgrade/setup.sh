#!/bin/bash
# Lab 07 setup: a workload that makes draining nodes non-trivial.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: uptime}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend, namespace: uptime}
spec:
  replicas: 4
  selector: {matchLabels: {app: frontend}}
  template:
    metadata: {labels: {app: frontend}}
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          readinessProbe: {httpGet: {path: /, port: 80}, periodSeconds: 2}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: frontend, namespace: uptime}
spec:
  minAvailable: 4
  selector: {matchLabels: {app: frontend}}
---
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: node-agent, namespace: uptime}
spec:
  selector: {matchLabels: {app: node-agent}}
  template:
    metadata: {labels: {app: node-agent}}
    spec:
      containers: [{name: agent, image: busybox:1.37, command: [sleep, infinity]}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: cache, namespace: uptime}
spec:
  replicas: 2
  selector: {matchLabels: {app: cache}}
  template:
    metadata: {labels: {app: cache}}
    spec:
      containers:
        - name: cache
          image: busybox:1.37
          command: [sh, -c, "echo warm > /data/state; sleep infinity"]
          volumeMounts: [{name: data, mountPath: /data}]
      volumes: [{name: data, emptyDir: {}}]
YAML
mkdir -p "$LAB_STATE"
kc -n uptime get pdb frontend -o jsonpath='{.metadata.uid}' >"$LAB_STATE/lab07-pdb-uid"
kc -n uptime rollout status deploy/frontend --timeout=180s >/dev/null
