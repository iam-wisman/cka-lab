#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "NodePort 30111 -> targetPort http-alt" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t11 get svc web -o json | jq -e '.spec.type==\"NodePort\" and any(.spec.ports[]; .nodePort==30111 and .targetPort==\"http-alt\")'"
check_eq "curl worker1:30111" "web e1" curl -s --max-time 5 http://worker1:30111
finish
