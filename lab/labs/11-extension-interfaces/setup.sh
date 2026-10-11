#!/bin/bash
# Lab 11 setup: a container started straight through containerd on worker1,
# invisible to Kubernetes.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
on worker1 bash -s <<'SH'
set -e
ctr -n k8s.io images pull -q docker.io/library/busybox:1.37 >/dev/null
ctr -n k8s.io tasks kill -s KILL rogue >/dev/null 2>&1 || true
sleep 1
ctr -n k8s.io containers rm rogue >/dev/null 2>&1 || true
ctr -n k8s.io run -d --label app=cryptominer docker.io/library/busybox:1.37 rogue sh -c 'while true; do sleep 1; done' >/dev/null
SH
mkdir -p "$HOME/answers" "$LAB_STATE"
on worker1 systemctl show containerd -p ActiveEnterTimestampMonotonic --value >"$LAB_STATE/lab11-containerd-start"
echo "Something is running on one of the workers that Kubernetes doesn't know about."
