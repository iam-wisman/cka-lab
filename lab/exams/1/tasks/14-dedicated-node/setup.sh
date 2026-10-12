#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t14 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t14 >/dev/null
kc taint node worker2 reserved=e1:NoSchedule --overwrite >/dev/null
