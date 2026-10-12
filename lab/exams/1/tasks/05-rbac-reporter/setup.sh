#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
for n in e1-t5 e1-apps; do kc delete ns $n --ignore-not-found --wait=true >/dev/null; kc create ns $n >/dev/null; done
kc delete clusterrole pod-reader-e1 --ignore-not-found >/dev/null
