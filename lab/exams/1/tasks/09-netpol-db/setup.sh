#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t9 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t9 >/dev/null
for a in frontend backend; do kc -n e1-t9 run $a --labels=app=$a --image=busybox:1.37 -- sleep infinity >/dev/null; done
kc -n e1-t9 run db --labels=app=db --image=busybox:1.37 -- sh -c 'while true; do nc -lk -p 5432 -e echo ok; done' >/dev/null
kc -n e1-t9 wait --for=condition=Ready pod --all --timeout=120s >/dev/null
