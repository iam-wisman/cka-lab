#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t10 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t10 >/dev/null
kc -n e2-t10 create deployment docs --image=hashicorp/http-echo:1.0 -- /http-echo -listen=:5678 -text="docs home" >/dev/null
kc -n e2-t10 expose deployment docs --port=80 --target-port=5678 >/dev/null
