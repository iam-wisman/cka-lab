#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "Secret orders-db key password" 'S3cure!2026' bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t3 get secret orders-db -o jsonpath='{.data.password}' | base64 -d"
check_eq "orders available" 1 kcq -n e1-t3 get deploy orders -o 'jsonpath={.status.availableReplicas}'
check_eq "Deployment not edited" "$(cat $LAB_STATE/exam1-t3-gen 2>/dev/null)" kcq -n e1-t3 get deploy orders -o 'jsonpath={.metadata.generation}'
finish
