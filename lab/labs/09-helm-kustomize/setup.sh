#!/bin/bash
# Lab 09 setup: the Kustomize base the overlay builds on.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
B=$HOME/kustomize/base
mkdir -p "$B" "$HOME/helm" "$HOME/answers"
cat >"$B/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  labels: {app: shop}
spec:
  replicas: 1
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop}
    spec:
      containers:
        - name: shop
          image: nginx:1.27-alpine
          ports: [{containerPort: 80, name: http}]
YAML
cat >"$B/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: shop
  labels: {app: shop}
spec:
  selector: {app: shop}
  ports: [{port: 80, targetPort: http}]
YAML
cat >"$B/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
YAML
echo "Base written to $B"
