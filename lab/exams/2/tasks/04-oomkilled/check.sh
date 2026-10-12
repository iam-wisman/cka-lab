#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "t4-exitcode.txt (SIGKILL from the OOM killer)" 137 cat "$HOME/exam2/t4-exitcode.txt"
check_eq "memory limit 256Mi" 256Mi kcq -n e2-t4 get deploy etl -o 'jsonpath={.spec.template.spec.containers[0].resources.limits.memory}'
check_eq "etl available" 1 kcq -n e2-t4 get deploy etl -o 'jsonpath={.status.availableReplicas}'
finish
