#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
obj() { kcq -n batch get "$1" -o json | jq -e "$2" >/dev/null; }

section "1: DaemonSet node-agent"
check "tolerates the control-plane taint" obj ds/node-agent 'any(.spec.template.spec.tolerations[]?; .key=="node-role.kubernetes.io/control-plane" or (.operator=="Exists" and (.key|not)))'
check "rolling update maxUnavailable 2" obj ds/node-agent '.spec.updateStrategy.rollingUpdate.maxUnavailable==2'
check_eq "running on all 5 nodes" 5 bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n batch get pod -l app=node-agent -o json | jq '[.items[] | select(.status.phase==\"Running\") | .spec.nodeName] | unique | length'"

section "2: StatefulSet kv"
check "Service kv is headless" obj svc/kv '.spec.clusterIP=="None"'
check "serviceName kv" obj sts/kv '.spec.serviceName=="kv"'
check "podManagementPolicy Parallel" obj sts/kv '.spec.podManagementPolicy=="Parallel"'
check_eq "3/3 ready" "3 3" kcq -n batch get sts kv -o 'jsonpath={.spec.replicas} {.status.readyReplicas}'
check_eq "answers/16-kv1-fqdn.txt" kv-1.kv.batch.svc.cka.local bash -c "sed 's/\.$//' ~/answers/16-kv1-fqdn.txt"
check "kv-1.kv.batch.svc.cka.local resolves to kv-1's IP" bash -c "
  ip=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n batch get pod kv-1 -o jsonpath='{.status.podIP}')
  [[ -n \$ip ]] && $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n batch exec kv-0 -- nslookup kv-1.kv.batch.svc.cka.local 2>/dev/null | grep -q \"\$ip\""

section "3: indexed Job shards"
check "Indexed, 6 completions, parallelism 2" obj job/shards '.spec.completionMode=="Indexed" and .spec.completions==6 and .spec.parallelism==2'
check "backoffLimitPerIndex 1" obj job/shards '.spec.backoffLimitPerIndex==1'
check "activeDeadlineSeconds 120" obj job/shards '.spec.activeDeadlineSeconds==120'
check "Complete with 6 succeeded" obj job/shards '.status.succeeded==6 and any(.status.conditions[]?; .type=="Complete" and .status=="True")'
check_match "index 3 printed 'processing shard 3'" 'processing shard 3' bash -c \
  "p=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n batch get pod -l job-name=shards,batch.kubernetes.io/job-completion-index=3 -o jsonpath='{.items[0].metadata.name}'); $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n batch logs \$p"

section "4: CronJob cleanup"
check "schedule every 5 min, timeZone America/New_York" obj cronjob/cleanup '.spec.schedule=="*/5 * * * *" and .spec.timeZone=="America/New_York"'
check "concurrencyPolicy Forbid" obj cronjob/cleanup '.spec.concurrencyPolicy=="Forbid"'
check "startingDeadlineSeconds 60" obj cronjob/cleanup '.spec.startingDeadlineSeconds==60'
check "history 2 successful / 1 failed" obj cronjob/cleanup '.spec.successfulJobsHistoryLimit==2 and .spec.failedJobsHistoryLimit==1'
check "Job cleanup-manual created from the CronJob" obj job/cleanup-manual '.metadata.annotations["cronjob.kubernetes.io/instantiate"]=="manual" and any(.metadata.ownerReferences[]?; .kind=="CronJob" and .name=="cleanup")'
check "cleanup-manual completed" obj job/cleanup-manual 'any(.status.conditions[]?; .type=="Complete" and .status=="True")'
finish
