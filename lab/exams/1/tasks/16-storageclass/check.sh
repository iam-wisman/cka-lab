#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "exam-retain: nfs.csi.k8s.io, same parameters as nfs-csi" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get sc exam-retain -o json | jq -c '[.provisioner, .parameters]') == \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get sc nfs-csi -o json | jq -c '[.provisioner, .parameters]') ]]"
check_eq "Retain + WaitForFirstConsumer" "Retain WaitForFirstConsumer" kcq get sc exam-retain -o 'jsonpath={.reclaimPolicy} {.volumeBindingMode}'
check_eq "nfs-csi is the only default" nfs-csi bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get sc -o json | jq -r '[.items[] | select(.metadata.annotations[\"storageclass.kubernetes.io/is-default-class\"]==\"true\") | .metadata.name] | join(\" \")'"
finish
