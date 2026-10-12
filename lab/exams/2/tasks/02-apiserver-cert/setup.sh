#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
on cp3 sed -i 's#--tls-cert-file=/etc/kubernetes/pki/apiserver.crt#--tls-cert-file=/etc/kubernetes/pki/apiserver-new.crt#' /etc/kubernetes/manifests/kube-apiserver.yaml
