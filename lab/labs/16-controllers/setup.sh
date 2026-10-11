#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace batch --ignore-not-found --wait=true >/dev/null
kc create namespace batch >/dev/null
