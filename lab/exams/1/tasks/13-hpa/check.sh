#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
h() { kcq -n e1-t13 get hpa worker -o json | jq -e "$1" >/dev/null; }
check "HPA worker 2-6, cpu 65%" h '.spec.minReplicas==2 and .spec.maxReplicas==6 and any(.spec.metrics[]; .resource.name=="cpu" and .resource.target.averageUtilization==65)'
check "metrics available (ScalingActive)" h 'any(.status.conditions[]; .type=="ScalingActive" and .status=="True")'
finish
