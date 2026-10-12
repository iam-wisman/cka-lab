#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
as=(--as system:serviceaccount:e1-t5:reporter)
yes_() { [[ $(kc auth can-i "$2" "$3" -n "$1" "${as[@]}" "${@:4}" 2>/dev/null) == yes ]]; }
no_() { [[ $(kc auth can-i "$2" "$3" -n "$1" "${as[@]}" "${@:4}" 2>/dev/null) == no ]]; }
check "ClusterRole pod-reader-e1 exists" kc get clusterrole pod-reader-e1
for n in e1-t5 e1-apps; do
  check "$n: list pods" yes_ $n list pods
  check "$n: get pods/log" yes_ $n get pods --subresource=log
  check "$n: cannot delete pods" no_ $n delete pods
done
check "default: cannot list pods" no_ default list pods
check "no ClusterRoleBinding grants it" bash -c "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterrolebinding -o json | jq -e 'any(.items[]; any(.subjects[]?; .kind==\"ServiceAccount\" and .name==\"reporter\"))' >/dev/null"
finish
