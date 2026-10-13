#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
drill_ns "$NS"
img=nginx:1.27-alpine env="" probe="" req="cpu: 50m"
case $FAULT in
  image) img=nginx:1.27-alpinee ;;
  configmap) env="envFrom: [{configMapRef: {name: $CM}}]"
             kc -n "$NS" create configmap "$CM-v2" --from-literal=MODE=prod >/dev/null ;;
  probe) probe="readinessProbe: {httpGet: {path: /, port: 8080}, periodSeconds: 3}" ;;
  request) req="cpu: \"64\"" ;;
esac
kc -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $DEP}
spec:
  replicas: $REP
  selector: {matchLabels: {app: $DEP}}
  template:
    metadata: {labels: {app: $DEP}}
    spec:
      containers:
        - name: web
          image: $img
          ports: [{containerPort: 80}]
          resources: {requests: {$req}}
          ${env}
          ${probe}
YAML
mkdir -p "$LAB_STATE/drills"
kc -n "$NS" get deploy "$DEP" -o jsonpath='{.metadata.uid}' >"$LAB_STATE/drills/$GRADE_ID.uid"
