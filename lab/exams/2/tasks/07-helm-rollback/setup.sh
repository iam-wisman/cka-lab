#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t7 --ignore-not-found --wait=true >/dev/null
helm repo add podinfo https://stefanprodan.github.io/podinfo >/dev/null 2>&1 || true
helm repo update podinfo >/dev/null 2>&1
helm install catalog podinfo/podinfo --version 6.14.1 -n e2-t7 --create-namespace --set replicaCount=2 --wait >/dev/null
helm upgrade catalog podinfo/podinfo --version 6.14.1 -n e2-t7 --set replicaCount=3 --wait >/dev/null
helm upgrade catalog podinfo/podinfo --version 6.14.1 -n e2-t7 --set replicaCount=3 --set image.tag=9.9.9-missing >/dev/null
