#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t10 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t10 >/dev/null
kc -n e1-t10 create deployment promo --image=hashicorp/http-echo:1.0 -- /http-echo -listen=:5678 -text=promo >/dev/null
kc -n e1-t10 expose deployment promo --port=80 --target-port=5678 >/dev/null
kc -n infra get gateway cka-gw -o jsonpath='{.metadata.generation}' >"$LAB_STATE/exam1-t10-gwgen" 2>/dev/null || true
