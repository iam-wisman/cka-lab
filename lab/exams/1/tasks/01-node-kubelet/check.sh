#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "worker2 Ready" True kcq get node worker2 -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
check "kubelet clientCAFile is the cluster CA" on worker2 grep -q 'clientCAFile: /etc/kubernetes/pki/ca.crt$' /var/lib/kubelet/config.yaml
check "kubelet enabled" on worker2 systemctl is-enabled -q kubelet
finish
