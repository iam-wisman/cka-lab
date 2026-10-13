#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
pj() { kcq -n "$NS" get pod "$POD" -o json | jq -e "$1" >/dev/null; }
check "image nginx:$TAG" pj ".spec.containers[0].image==\"nginx:$TAG\""
check "label tier=$TIER" pj ".metadata.labels.tier==\"$TIER\""
check "requests ${CPU}m CPU, ${MEM}Mi memory" pj ".spec.containers[0].resources.requests == {\"cpu\":\"${CPU}m\",\"memory\":\"${MEM}Mi\"}"
check "memory limit ${MEMLIM}Mi, no CPU limit" pj ".spec.containers[0].resources.limits == {\"memory\":\"${MEMLIM}Mi\"}"
check "Running" pj '.status.phase=="Running"'
finish
