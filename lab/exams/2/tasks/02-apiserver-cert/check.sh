#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "manifest uses pki/apiserver.crt" on cp3 grep -q -- '--tls-cert-file=/etc/kubernetes/pki/apiserver.crt' /etc/kubernetes/manifests/kube-apiserver.yaml
check_eq "cp3 UP in HAProxy" UP bash -c "curl -sf --max-time 5 'http://10.10.10.10:8404/stats;csv' | awk -F, '\$2==\"cp3\" {print \$18; exit}'"
check_eq "kube-apiserver-cp3 Running" Running kcq -n kube-system get pod kube-apiserver-cp3 -o 'jsonpath={.status.phase}'
finish
