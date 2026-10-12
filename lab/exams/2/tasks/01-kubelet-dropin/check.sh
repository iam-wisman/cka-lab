#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "worker1 Ready" True kcq get node worker1 -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
check "kubelet active" on worker1 systemctl is-active -q kubelet
check "no invalid --fail-swap-on value left in the unit" on worker1 bash -c '! systemctl cat kubelet | grep -q "fail-swap-on=maybe"'
finish
