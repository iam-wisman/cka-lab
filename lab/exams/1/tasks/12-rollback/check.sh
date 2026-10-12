#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "image nginx:1.26-alpine" nginx:1.26-alpine kcq -n e1-t12 get deploy api -o 'jsonpath={.spec.template.spec.containers[0].image}'
check_eq "2/2 available, rollout complete" "2 2" kcq -n e1-t12 get deploy api -o 'jsonpath={.status.availableReplicas} {.status.updatedReplicas}'
check_eq "t12-image.txt" nginx:1.26-alpine cat "$HOME/exam1/t12-image.txt"
finish
