#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace storage --ignore-not-found --wait=true >/dev/null
kc create namespace storage >/dev/null
