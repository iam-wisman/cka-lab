#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace team-a --ignore-not-found --wait=true >/dev/null
kc create namespace team-a >/dev/null
# Undo lab 17's dedicated-node taint so this and later labs can use both workers.
kc taint node worker2 dedicated- >/dev/null 2>&1 || true
on worker1 rm -f /etc/kubernetes/manifests/static-web.yaml
mkdir -p "$HOME/answers"
