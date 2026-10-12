#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
K=("$GRADER_KUBECTL" --kubeconfig "$HOME/exam2/eve.kubeconfig" --request-timeout=10s)
check_eq "kubeconfig authenticates as eve" eve "${K[@]}" auth whoami -o 'jsonpath={.status.userInfo.username}'
check "eve can list deployments in e2-t5" "${K[@]}" -n e2-t5 get deployments
check "eve cannot list pods in e2-t5" bash -c "! $GRADER_KUBECTL --kubeconfig $HOME/exam2/eve.kubeconfig -n e2-t5 get pods >/dev/null 2>&1"
check "eve cannot create deployments" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG auth can-i create deployments -n e2-t5 --as eve --as-group ops) == no ]]"
finish
