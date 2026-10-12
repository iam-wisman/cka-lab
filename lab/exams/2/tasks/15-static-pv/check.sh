#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "PV e2-data Bound to e2-t15/e2-data" "Bound e2-data manual" kcq get pv e2-data -o 'jsonpath={.status.phase} {.spec.claimRef.name} {.spec.storageClassName}'
check_eq "viewer reads README" "exam2 data" kc -n e2-t15 exec viewer -- cat /data/README
finish
