#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t11 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t11 >/dev/null
kc -n e2-t11 run client --labels=app=client --image=busybox:1.37 -- sleep infinity >/dev/null
kc -n e2-t11 create deployment api --image=hashicorp/http-echo:1.0 -- /http-echo -listen=:80 -text=api >/dev/null
kc -n e2-t11 expose deployment api --port=80 >/dev/null
kc -n e2-t11 wait --for=condition=Ready pod --all --timeout=120s >/dev/null
