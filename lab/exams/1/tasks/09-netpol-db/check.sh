#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
ip=$(kcq -n e1-t9 get pod db -o 'jsonpath={.status.podIP}')
tcp() { kc -n e1-t9 exec "$1" -- nc -z -w 3 "$ip" 5432 >/dev/null 2>&1; }
notcp() { ! tcp "$1"; }
check "NetworkPolicy db-access selects app=db" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t9 get networkpolicy db-access -o json | jq -e '.spec.podSelector.matchLabels.app==\"db\"'"
check "backend -> db:5432 allowed" tcp backend
check "frontend -> db:5432 refused" notcp frontend
check "frontend -> backend still open (no namespace-wide deny)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t9 get networkpolicy -o json | jq -e '[.items[] | select(.spec.podSelector=={})] | length==0'"
finish
