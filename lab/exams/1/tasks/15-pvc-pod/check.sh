#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "PVC scratch Bound, 500Mi, RWO, nfs-csi" "Bound 500Mi ReadWriteOnce nfs-csi" kcq -n e1-t15 get pvc scratch -o 'jsonpath={.status.phase} {.spec.resources.requests.storage} {.spec.accessModes[0]} {.spec.storageClassName}'
check_eq "marker on the volume" exam1 kc -n e1-t15 exec writer -- cat /scratch/marker
check "mounted from the PVC" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t15 get pod writer -o json | jq -e 'any(.spec.volumes[]; .persistentVolumeClaim.claimName==\"scratch\")'"
finish
