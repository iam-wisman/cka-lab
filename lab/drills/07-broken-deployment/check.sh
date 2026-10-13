#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
dj() { kcq -n "$NS" get deploy "$DEP" -o json | jq -e "$1" >/dev/null; }
check "same Deployment (not deleted and recreated)" dj ".metadata.uid==\"$(cat "$LAB_STATE/drills/$GRADE_ID.uid" 2>/dev/null)\""
check "still $REP replicas" dj ".spec.replicas==$REP"
check "all $REP ready and available" dj ".status.readyReplicas==$REP and .status.availableReplicas==$REP and (.status.unavailableReplicas // 0)==0"
finish
