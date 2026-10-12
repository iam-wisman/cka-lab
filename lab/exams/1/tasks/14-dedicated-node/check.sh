#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "batch Running on worker2" "Running worker2" kcq -n e1-t14 get pod batch -o 'jsonpath={.status.phase} {.spec.nodeName}'
check "tolerates reserved=e1:NoSchedule" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t14 get pod batch -o json | jq -e 'any(.spec.tolerations[]; .key==\"reserved\")'"
check "pinned to worker2 by selector/affinity, not just luck" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t14 get pod batch -o json | jq -e '.spec | (.nodeSelector // {} | length > 0) or (.affinity.nodeAffinity != null) or (.nodeName == \"worker2\")'"
finish
