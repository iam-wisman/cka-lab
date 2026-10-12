#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t12 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t12 >/dev/null
kc -n e1-t12 create deployment api --image=nginx:1.25-alpine --replicas=2 >/dev/null
kc -n e1-t12 rollout status deploy/api --timeout=120s >/dev/null
kc -n e1-t12 set image deploy/api nginx=nginx:1.26-alpine >/dev/null
kc -n e1-t12 rollout status deploy/api --timeout=120s >/dev/null
kc -n e1-t12 set image deploy/api nginx=nginx:1.26-alpine-broken >/dev/null
