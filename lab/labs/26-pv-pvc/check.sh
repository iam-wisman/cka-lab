#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
pv() { kcq get pv "$1" -o json | jq -e "$2" >/dev/null; }
pvc() { kcq -n pv-lab get pvc "$1" -o json | jq -e "$2" >/dev/null; }

section "1: Released PV reused"
check_eq "archive-pv is the original PV object" "$(cat "$LAB_STATE/lab26-archive-uid" 2>/dev/null)" kcq get pv archive-pv -o 'jsonpath={.metadata.uid}'
check "archive-pv Bound to pv-lab/archive" pv archive-pv '.status.phase=="Bound" and .spec.claimRef.namespace=="pv-lab" and .spec.claimRef.name=="archive"'
check "PVC archive pins volumeName archive-pv with storageClassName \"\"" pvc archive '.spec.volumeName=="archive-pv" and .spec.storageClassName==""'
check_match "reader sees important.txt" 'Q3 ledger close' kc -n pv-lab exec reader -- cat /archive/important.txt

section "2: local PV"
check "StorageClass local-storage: no-provisioner, WaitForFirstConsumer" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get sc local-storage -o json | jq -e '.provisioner==\"kubernetes.io/no-provisioner\" and .volumeBindingMode==\"WaitForFirstConsumer\"'"
check "PV local-vol1: local /mnt/disks/vol1, RWO, 1Gi, nodeAffinity worker1" pv local-vol1 \
  '.spec.local.path=="/mnt/disks/vol1" and .spec.accessModes==["ReadWriteOnce"] and .spec.capacity.storage=="1Gi" and .spec.storageClassName=="local-storage"
   and any(.spec.nodeAffinity.required.nodeSelectorTerms[].matchExpressions[]; .key=="kubernetes.io/hostname" and (.values|index("worker1")))'
check "PVC fast Bound to local-vol1" pvc fast '.status.phase=="Bound" and .spec.volumeName=="local-vol1"'
check_eq "fast-consumer Running on worker1" "Running worker1" kcq -n pv-lab get pod fast-consumer -o 'jsonpath={.status.phase} {.spec.nodeName}'
check "fast-consumer has no nodeName/nodeSelector/affinity of its own" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get pod fast-consumer -o json | jq -e '(.spec.nodeSelector|not) and (.spec.affinity|not)' && $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get events --field-selector involvedObject.name=fast-consumer,reason=Scheduled -o name | grep -q ."

section "3: ReadWriteOncePod"
check "PVC exclusive: ReadWriteOncePod, nfs-csi" pvc exclusive '.spec.accessModes==["ReadWriteOncePod"] and .spec.storageClassName=="nfs-csi"'
check_eq "solo Running" Running kcq -n pv-lab get pod solo -o 'jsonpath={.status.phase}'
check "second Pending, refused for the RWOP claim" bash -c \
  "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get pod second -o jsonpath='{.status.phase}') == Pending ]] &&
   $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get pod second -o json | jq -e '.spec.volumes | any(.persistentVolumeClaim.claimName==\"exclusive\")' >/dev/null &&
   $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get events --field-selector involvedObject.name=second,reason=FailedScheduling -o jsonpath='{.items[*].message}' | grep -qi 'ReadWriteOncePod'"

section "4: expansion"
check_eq "growing: spec 3Gi" 3Gi kcq -n pv-lab get pvc growing -o 'jsonpath={.spec.resources.requests.storage}'
check_eq "growing: capacity 3Gi" 3Gi kcq -n pv-lab get pvc growing -o 'jsonpath={.status.capacity.storage}'

section "5: StatefulSet retention"
check "persistentVolumeClaimRetentionPolicy whenDeleted Delete, whenScaled Retain" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get sts ledger -o json | jq -e '.spec.persistentVolumeClaimRetentionPolicy == {\"whenDeleted\":\"Delete\",\"whenScaled\":\"Retain\"}'"
check_eq "scaled to 2, both ready" "2 2" kcq -n pv-lab get sts ledger -o 'jsonpath={.spec.replicas} {.status.readyReplicas}'
check "data-ledger-0, -1 and -2 all exist (scale-down kept -2)" bash -c \
  "for i in 0 1 2; do $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n pv-lab get pvc data-ledger-\$i >/dev/null || exit 1; done"
finish
