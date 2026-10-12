#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "capacity 4Gi" 4Gi kcq -n e2-t16 get pvc logs -o 'jsonpath={.status.capacity.storage}'
check_eq "same PVC object" "$(cat $LAB_STATE/exam2-t16-uid 2>/dev/null)" kcq -n e2-t16 get pvc logs -o 'jsonpath={.metadata.uid}'
finish
