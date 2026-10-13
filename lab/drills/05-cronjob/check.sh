#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
cj() { kcq -n "$NS" get cronjob "$CJ" -o json | jq -e "$1" >/dev/null; }
check "every $EVERY minutes" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get cronjob $CJ -o jsonpath='{.spec.schedule}' | grep -Eq '^(\\*|0)/$EVERY \\* \\* \\* \\*\$'"
check "never overlaps" cj '.spec.concurrencyPolicy=="Forbid"'
check "keeps $KEEP successful, 1 failed" cj ".spec.successfulJobsHistoryLimit==$KEEP and .spec.failedJobsHistoryLimit==1"
check "killed after ${DEADLINE}s" cj ".spec.jobTemplate.spec.activeDeadlineSeconds==$DEADLINE"
check "restartPolicy Never" cj '.spec.jobTemplate.spec.template.spec.restartPolicy=="Never"'
check "busybox:1.37 prints $WORD" cj ".spec.jobTemplate.spec.template.spec.containers[0] | .image==\"busybox:1.37\" and (((.command // []) + (.args // [])) | join(\" \") | contains(\"$WORD\"))"
check "Job $CJ-now was created from the CronJob" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get job $CJ-now -o json | jq -e '.metadata.annotations[\"cronjob.kubernetes.io/instantiate\"]==\"manual\"' >/dev/null"
check "$CJ-now completed" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get job $CJ-now -o json | jq -e '.status.succeeded==1' >/dev/null"
check_eq "and printed $WORD" "$WORD" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS logs job/$CJ-now 2>/dev/null | tr -d '[:space:]'"
finish
