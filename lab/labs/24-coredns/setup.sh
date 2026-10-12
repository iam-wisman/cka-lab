#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace dns --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: dns}
---
apiVersion: v1
kind: Pod
metadata: {name: probe, namespace: dns}
spec: {containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]}
---
apiVersion: v1
kind: Service
metadata: {name: catalog, namespace: dns}
spec: {selector: {app: catalog}, ports: [{port: 80}]}
YAML
kc -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' >"$LAB_STATE/lab24-corefile-before" 2>/dev/null || true
mkdir -p "$HOME/answers"
