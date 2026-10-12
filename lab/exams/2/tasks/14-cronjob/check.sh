#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "schedule and history" "*/15 * * * * 3" kcq -n e2-t14 get cronjob report -o 'jsonpath={.spec.schedule} {.spec.successfulJobsHistoryLimit}'
check "report-now from the CronJob, completed" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e2-t14 get job report-now -o json | jq -e 'any(.metadata.ownerReferences[]?; .kind==\"CronJob\" and .name==\"report\") and any(.status.conditions[]?; .type==\"Complete\" and .status==\"True\")'"
finish
