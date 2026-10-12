#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t15 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t15 >/dev/null
