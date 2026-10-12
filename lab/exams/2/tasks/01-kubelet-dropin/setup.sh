#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
on worker1 bash -c 'mkdir -p /etc/systemd/system/kubelet.service.d && printf "[Service]\nEnvironment=\"KUBELET_EXTRA_ARGS=--fail-swap-on=maybe\"\n" > /etc/systemd/system/kubelet.service.d/20-hardening.conf && systemctl daemon-reload && systemctl restart kubelet'
