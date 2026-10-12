#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "stg-api: 2 available" 2 kcq -n e1-t8 get deploy stg-api -o 'jsonpath={.status.availableReplicas}'
check_eq "label env=staging on the Deployment" staging kcq -n e1-t8 get deploy stg-api -o 'jsonpath={.metadata.labels.env}'
check_eq "label env=staging on namespace e1-t8 (created by the overlay)" staging kcq get ns e1-t8 -o 'jsonpath={.metadata.labels.env}'
check "overlay renders" kc kustomize "$HOME/exam1/t8/staging"
finish
