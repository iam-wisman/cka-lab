#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
nj() { kcq -n "$NS" get networkpolicy "$NP" -o json | jq -e "$1" >/dev/null; }
ip=$(kcq -n "$NS" get pod -l app=api -o 'jsonpath={.items[0].status.podIP}')
from() { kc -n "$NS" exec "$1" -- wget -qO- -T 3 "http://$ip:$APORT" 2>/dev/null; }
check "policy $NP selects app=api" nj '.spec.podSelector.matchLabels.app=="api"'
check "it doesn't restrict egress" nj '(.spec.policyTypes // ["Ingress"]) | index("Egress") | not'
check_eq "$GOOD (role=$ROLE) reaches api:$APORT" ok from "$GOOD"
check "intruder (role=guest) is blocked" bash -c "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS exec intruder -- wget -qO- -T 3 http://$ip:$APORT >/dev/null 2>&1"
check "pods in other namespaces are blocked, even with role=$ROLE" bash -c "
  $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n default run drill-probe-\$\$ --rm -i --restart=Never --image=busybox:1.37 -l role=$ROLE --quiet -- wget -qO- -T 3 http://$ip:$APORT 2>/dev/null | grep -q ok && exit 1 || exit 0"
check "only TCP $APORT is allowed" nj "([.spec.ingress[]? | .ports[]?] | length > 0) and all(.spec.ingress[]? | .ports[]?; .port==$APORT and ((.protocol // \"TCP\")==\"TCP\")) and all(.spec.ingress[]?; .ports != null)"
finish
