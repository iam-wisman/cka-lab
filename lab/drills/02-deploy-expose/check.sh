#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
dj() { kcq -n "$NS" get deploy "$DEP" -o json | jq -e "$1" >/dev/null; }
sj() { kcq -n "$NS" get svc "$SVC" -o json | jq -e "$1" >/dev/null; }
check "deployment: $REP replicas of httpd:2.4-alpine, all ready" dj ".spec.replicas==$REP and .status.readyReplicas==$REP and .spec.template.spec.containers[0].image==\"httpd:2.4-alpine\""
check "container port 80 named web" dj 'any(.spec.template.spec.containers[0].ports[]?; .containerPort==80 and .name=="web")'
check "service: ClusterIP, port $PORT -> targetPort web" sj ".spec.type==\"ClusterIP\" and any(.spec.ports[]; .port==$PORT and .targetPort==\"web\")"
check_eq "$REP ready endpoints" "$REP" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get endpointslices -l kubernetes.io/service-name=$SVC -o json | jq '[.items[].endpoints[]? | select(.conditions.ready)] | length'"
finish
