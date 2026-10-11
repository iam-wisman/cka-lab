#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace team-a --ignore-not-found --wait=true >/dev/null
kc create namespace team-a >/dev/null
on worker1 rm -f /etc/kubernetes/manifests/static-web.yaml
mkdir -p "$HOME/answers"
