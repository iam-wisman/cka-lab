#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t14 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t14 >/dev/null
