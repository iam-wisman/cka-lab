#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "5 pods ready, one per node" "5 5" kcq -n e2-t13 get ds log-agent -o 'jsonpath={.status.desiredNumberScheduled} {.status.numberReady}'
finish
