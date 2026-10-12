#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
r=$(helm_release e1-t7 frontend)
check_eq "chart podinfo 6.14.1" "podinfo 6.14.1" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${r:-{\}}"
check_eq "3 replicas available" 3 kcq -n e1-t7 get deploy frontend-podinfo -o 'jsonpath={.status.availableReplicas}'
check "UI message 'exam one'" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t7 get deploy frontend-podinfo -o json | jq -e '[.spec.template.spec.containers[0].env[]? | select(.name==\"PODINFO_UI_MESSAGE\") | .value] == [\"exam one\"]'"
finish
