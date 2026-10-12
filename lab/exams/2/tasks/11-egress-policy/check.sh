#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
x() { kc -n e2-t11 exec client -- "$@" >/dev/null 2>&1; }
nx() { ! x "$@"; }
check "client -> api:80 works by name" x wget -qO- -T 4 http://api
check "client -> internet blocked" nx nc -z -w 3 1.1.1.1 443
check "client -> jump ssh blocked" nx nc -z -w 3 10.10.10.10 22
check "policy client-egress selects app=client, Egress" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e2-t11 get networkpolicy client-egress -o json | jq -e '.spec.podSelector.matchLabels.app==\"client\" and (.spec.policyTypes|index(\"Egress\"))'"
finish
