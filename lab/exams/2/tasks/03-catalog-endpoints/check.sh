#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "catalog answers in-cluster" "catalog v2" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e2-t3 run probe-\$RANDOM --rm -i --restart=Never --image=busybox:1.37 -q -- wget -qO- -T 5 http://catalog 2>/dev/null"
check "Deployment unchanged (generation 1)" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e2-t3 get deploy catalog -o jsonpath='{.metadata.generation}') == 1 ]]"
finish
