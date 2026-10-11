#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace heal --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: heal}
---
# Takes ~40s to start serving; the liveness probe kills it long before that.
apiVersion: apps/v1
kind: Deployment
metadata: {name: slowapp, namespace: heal}
spec:
  replicas: 3
  selector: {matchLabels: {app: slowapp}}
  template:
    metadata: {labels: {app: slowapp}}
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: [sh, -c, "echo warming caches; sleep 40; mkdir -p /www; echo ok > /www/healthz; echo ready > /www/ready; exec httpd -f -p 8080 -h /www"]
          ports: [{containerPort: 8080, name: http}]
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 5
            failureThreshold: 3
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: logger, namespace: heal}
spec:
  replicas: 1
  selector: {matchLabels: {app: logger}}
  template:
    metadata: {labels: {app: logger}}
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: [sh, -c, "i=0; while true; do i=$((i+1)); echo \"$(date -u +%T) order $i processed\" >> /var/log/app/app.log; sleep 2; done"]
          volumeMounts: [{name: logs, mountPath: /var/log/app}]
      volumes: [{name: logs, emptyDir: {}}]
YAML
