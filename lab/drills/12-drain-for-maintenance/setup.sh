#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
drill_ns "$NS"
kc -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $DEP}
spec:
  replicas: 4
  selector: {matchLabels: {app: $DEP}}
  template:
    metadata: {labels: {app: $DEP}}
    spec:
      topologySpreadConstraints: [{maxSkew: 1, topologyKey: kubernetes.io/hostname, whenUnsatisfiable: ScheduleAnyway, labelSelector: {matchLabels: {app: $DEP}}}]
      volumes: [{name: scratch, emptyDir: {}}]
      containers:
        - {name: c, image: nginx:1.27-alpine, volumeMounts: [{name: scratch, mountPath: /cache}]}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: $DEP}
spec: {minAvailable: 3, selector: {matchLabels: {app: $DEP}}}
YAML
kc -n "$NS" rollout status "deploy/$DEP" --timeout=180s >/dev/null
mkdir -p "$LAB_STATE/drills"
kc -n "$NS" get pdb "$DEP" -o jsonpath='{.metadata.uid}' >"$LAB_STATE/drills/$GRADE_ID.uid"
