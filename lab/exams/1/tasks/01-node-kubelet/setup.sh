#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
on worker2 bash -c "sed -i 's#clientCAFile: /etc/kubernetes/pki/ca.crt#clientCAFile: /etc/kubernetes/pki/ca-bundle.crt#' /var/lib/kubelet/config.yaml && systemctl restart kubelet"
