#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "$NODE is cordoned" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node $NODE -o json | jq -e '.spec.unschedulable==true' >/dev/null"
check_eq "only DaemonSet pods left on $NODE" 0 bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get pods -A --field-selector spec.nodeName=$NODE -o json | jq '[.items[] | select(.metadata.deletionTimestamp|not) | select(([.metadata.ownerReferences[]?.kind] | index(\"DaemonSet\")) | not) | select(.metadata.annotations[\"kubernetes.io/config.mirror\"]|not)] | length'"
check "$DEP has 4 ready replicas" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get deploy $DEP -o json | jq -e '.status.readyReplicas==4' >/dev/null"
check "PDB untouched (same object, minAvailable 3)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get pdb $DEP -o json | jq -e '.metadata.uid==\"$(cat "$LAB_STATE/drills/$GRADE_ID.uid" 2>/dev/null)\" and .spec.minAvailable==3' >/dev/null"
finish
