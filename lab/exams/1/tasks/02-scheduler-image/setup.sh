#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t2 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t2 >/dev/null
kc -n e1-t2 create deployment probe --image=nginx:1.27-alpine --replicas=2 >/dev/null
on cp1 sed -ri 's#(image: registry.k8s.io/kube-scheduler:)v[0-9.]+#\1v1.35.99#' /etc/kubernetes/manifests/kube-scheduler.yaml
