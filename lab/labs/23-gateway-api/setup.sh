#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"

# Phase "rogue": only plant the untrusted route; never touch the student's work.
if [[ ${1:-} == rogue ]]; then
  kc get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 || die "install Envoy Gateway first (it brings the Gateway API CRDs)"
  kc apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: admin, namespace: rogue}
spec:
  parentRefs: [{name: cka-gw, namespace: infra}]
  hostnames: [store.cka.lab]
  rules:
    - matches: [{path: {type: PathPrefix, value: /admin}}]
      backendRefs: [{name: admin, port: 80}]
YAML
  echo "rogue/admin HTTPRoute created."
  exit 0
fi
for ns in store legacy rogue; do kc delete namespace $ns --ignore-not-found --wait=true >/dev/null; done
kc create namespace store >/dev/null
kc label namespace store gateway-access=true --overwrite >/dev/null
kc create namespace legacy >/dev/null
kc create namespace rogue >/dev/null
kc create namespace infra --dry-run=client -o yaml | kc apply -f - >/dev/null
mk() { # mk <ns> <name> <text>
  kc apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $2, namespace: $1}
spec:
  replicas: 1
  selector: {matchLabels: {app: $2}}
  template:
    metadata: {labels: {app: $2}}
    spec:
      containers:
        - {name: $2, image: hashicorp/http-echo:1.0, args: ["-listen=:5678", "-text=$3"], ports: [{containerPort: 5678}]}
---
apiVersion: v1
kind: Service
metadata: {name: $2, namespace: $1}
spec: {selector: {app: $2}, ports: [{port: 80, targetPort: 5678}]}
YAML
}
mk store v1 v1; mk store v2 v2; mk legacy legacy legacy; mk rogue admin pwned
echo "Namespaces store (label gateway-access=true), legacy and rogue are ready."
echo "After installing Envoy Gateway, run: lab start 23 rogue"
