#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
nj() { kcq get node "$NODE" -o json | jq -e "$1" >/dev/null; }
pj() { kcq -n "$NS" get pod "$POD" -o json | jq -e "$1" >/dev/null; }
check "$NODE tainted dedicated=$TEAM:NoSchedule" nj "any(.spec.taints[]?; .key==\"dedicated\" and .value==\"$TEAM\" and .effect==\"NoSchedule\")"
check "$NODE labelled team=$TEAM" nj ".metadata.labels.team==\"$TEAM\""
check "$POD tolerates the taint" pj "any(.spec.tolerations[]?; .key==\"dedicated\" and (.operator==\"Exists\" or .value==\"$TEAM\") and ((.effect // \"NoSchedule\")==\"NoSchedule\"))"
check "$POD is pinned to team=$TEAM nodes" pj "(.spec.nodeSelector.team==\"$TEAM\") or any(.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]?.matchExpressions[]?; .key==\"team\" and .operator==\"In\" and (.values|index(\"$TEAM\")))"
check "$POD runs on $NODE" pj ".spec.nodeName==\"$NODE\" and .status.phase==\"Running\""
finish
