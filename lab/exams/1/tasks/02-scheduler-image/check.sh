#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_match "cp1 scheduler image is v1.35.9" 'kube-scheduler:v1\.35\.9$' on cp1 grep -o 'image: .*kube-scheduler:.*' /etc/kubernetes/manifests/kube-scheduler.yaml
check_eq "kube-scheduler-cp1 Running" Running kcq -n kube-system get pod kube-scheduler-cp1 -o 'jsonpath={.status.phase}'
check_eq "probe 2/2 available" 2 kcq -n e1-t2 get deploy probe -o 'jsonpath={.status.availableReplicas}'
finish
