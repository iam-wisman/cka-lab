#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
want=nginx:1.25-alpine; [[ $TARGET == 2 ]] && want=nginx:1.26-alpine
dj() { kcq -n "$NS" get deploy "$DEP" -o json | jq -e "$1" >/dev/null; }
check "running $want (the $CAUSE revision)" dj ".spec.template.spec.containers[0].image==\"$want\""
check "rollouts paused" dj '.spec.paused==true'
check "all replicas ready on $want" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get pods -l app=$DEP -o json | jq -r '[.items[] | select(.metadata.deletionTimestamp|not) | select(.spec.containers[0].image==\"$want\" and any(.status.conditions[]?; .type==\"Ready\" and .status==\"True\"))] | length') -ge 2 ]]"
finish
