#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
hpa() { kcq -n scale get hpa api -o json | jq -e "$1" >/dev/null; }

section "A: HPA"
check "autoscaling/v2 HPA api targets Deployment api" hpa '.spec.scaleTargetRef.kind=="Deployment" and .spec.scaleTargetRef.name=="api"'
check "min 2, max 8" hpa '.spec.minReplicas==2 and .spec.maxReplicas==8'
check "CPU: Utilization 50" hpa 'any(.spec.metrics[]; .type=="Resource" and .resource.name=="cpu" and .resource.target.type=="Utilization" and .resource.target.averageUtilization==50)'
check "memory: AverageValue 100Mi" hpa 'any(.spec.metrics[]; .type=="Resource" and .resource.name=="memory" and .resource.target.type=="AverageValue" and .resource.target.averageValue=="100Mi")'
check "scaleUp: 100 percent per 15s" hpa 'any(.spec.behavior.scaleUp.policies[]; .type=="Percent" and .value==100 and .periodSeconds==15)'
check "scaleUp: no stricter policy wins (selectPolicy Max or single policy)" hpa '(.spec.behavior.scaleUp.selectPolicy // "Max") == "Max"'
check "scaleDown: stabilization 120s" hpa '.spec.behavior.scaleDown.stabilizationWindowSeconds==120'
check "scaleDown: 1 pod per 60s" hpa '.spec.behavior.scaleDown.policies == [{"type":"Pods","value":1,"periodSeconds":60}]'
check_eq "Deployment requests cpu 100m memory 64Mi" "100m 64Mi" kcq -n scale get deploy api -o 'jsonpath={.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory}'
check "ScalingActive=True (metrics available)" hpa 'any(.status.conditions[]; .type=="ScalingActive" and .status=="True")'
check "current CPU and memory metrics reported" hpa '[.status.currentMetrics[]?.resource.name] | (index("cpu") != null and index("memory") != null)'
check "at least 2 replicas running" bash -c "(( \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n scale get deploy api -o jsonpath='{.status.availableReplicas}') >= 2 ))"

section "B: in-place resize"
pod() { kcq -n scale get pod resizer -o json | jq -e "$1" >/dev/null; }
check "pod resizer exists" pod '.metadata.name=="resizer"'
check "resizePolicy: cpu NotRequired" pod 'any(.spec.containers[0].resizePolicy[]; .resourceName=="cpu" and .restartPolicy=="NotRequired")'
check "resizePolicy: memory RestartContainer" pod 'any(.spec.containers[0].resizePolicy[]; .resourceName=="memory" and .restartPolicy=="RestartContainer")'
check "spec: cpu 250m/500m, memory 64Mi/192Mi" pod '.spec.containers[0].resources == {"requests":{"cpu":"250m","memory":"64Mi"},"limits":{"cpu":"500m","memory":"192Mi"}}'
check "status: kubelet applied the new resources" pod '.status.containerStatuses[0].resources == .spec.containers[0].resources'
check "no resize pending or in progress" pod '[.status.conditions[]? | select(.type=="PodResizePending" or .type=="PodResizeInProgress")] | length == 0'
check_eq "container restarted exactly once (memory change only)" 1 kcq -n scale get pod resizer -o 'jsonpath={.status.containerStatuses[0].restartCount}'
finish
