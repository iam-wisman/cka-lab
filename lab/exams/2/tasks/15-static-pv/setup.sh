#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t15 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t15 >/dev/null
kc delete pv e2-data --ignore-not-found >/dev/null
on worker1 bash -c 'mkdir -p /mnt/e2-data && echo "exam2 data" > /mnt/e2-data/README'
