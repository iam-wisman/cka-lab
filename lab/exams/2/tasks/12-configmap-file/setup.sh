#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t12 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t12 >/dev/null
kc -n e2-t12 create deployment app --image=busybox:1.37 -- sh -c 'sleep infinity' >/dev/null
