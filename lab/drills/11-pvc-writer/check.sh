#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
pv() { kcq -n "$NS" get pvc "$PVC" -o json | jq -e "$1" >/dev/null; }
pj() { kcq -n "$NS" get pod "$POD" -o json | jq -e "$1" >/dev/null; }
check "PVC $PVC: ${SIZE}Gi RWO from nfs-csi, Bound" pv ".spec.storageClassName==\"nfs-csi\" and .spec.resources.requests.storage==\"${SIZE}Gi\" and .spec.accessModes==[\"ReadWriteOnce\"] and .status.phase==\"Bound\""
check "$POD mounts it at /data" pj "any(.spec.volumes[]?; .persistentVolumeClaim.claimName==\"$PVC\") and any(.spec.containers[0].volumeMounts[]?; .mountPath==\"/data\")"
check "$POD is Running" pj '.status.phase=="Running"'
check_eq "/data/$FILE.txt holds $WORD" "$WORD" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS exec $POD -- cat /data/$FILE.txt 2>/dev/null | tr -d '[:space:]'"
finish
