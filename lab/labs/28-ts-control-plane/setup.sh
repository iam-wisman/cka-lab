#!/bin/bash
# Lab 28 setup: one fault per control plane. HA hides all three.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
M=/etc/kubernetes/manifests
on cp1 sed -i 's#--kubeconfig=/etc/kubernetes/scheduler.conf#--kubeconfig=/etc/kubernetes/scheduler.cfg#' $M/kube-scheduler.yaml
on cp2 sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2381#' $M/kube-apiserver.yaml
on cp3 sed -i 's#--cluster-signing-key-file=/etc/kubernetes/pki/ca.key#--cluster-signing-key-file=/etc/kubernetes/pki/ca.pem#' $M/kube-controller-manager.yaml
echo "The cluster still works... or does it? Investigate the control plane."
