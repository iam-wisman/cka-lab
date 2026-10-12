#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
dep() { kcq -n heal get deploy "$1" -o json | jq -e "$2" >/dev/null; }
S='.spec.template.spec.containers[] | select(.name=="app")'

section "1: slowapp probes"
check "liveness unchanged: /healthz on http, period 5, failureThreshold 3" dep slowapp \
  "$S | .livenessProbe.httpGet.path==\"/healthz\" and (.livenessProbe.httpGet.port==\"http\" or .livenessProbe.httpGet.port==8080) and .livenessProbe.periodSeconds==5 and .livenessProbe.failureThreshold==3"
check "startupProbe on /healthz" dep slowapp "$S | .startupProbe.httpGet.path==\"/healthz\""
check "startupProbe allows >= 90s (failureThreshold x periodSeconds)" dep slowapp \
  "$S | ((.startupProbe.failureThreshold // 3) * (.startupProbe.periodSeconds // 10)) + (.startupProbe.initialDelaySeconds // 0) >= 90"
check "readinessProbe on /ready every 5s" dep slowapp "$S | .readinessProbe.httpGet.path==\"/ready\" and .readinessProbe.periodSeconds==5"
check_eq "3/3 ready" "3 3" kcq -n heal get deploy slowapp -o 'jsonpath={.spec.replicas} {.status.readyReplicas}'
check "current pods have 0 restarts (terminating old pods ignored)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n heal get pod -l app=slowapp -o json | jq -e '[.items[] | select(.metadata.deletionTimestamp == null)] | (length)>0 and all(.[]; .status.containerStatuses[0].restartCount==0)'"

section "2: PDB"
check "PDB slowapp: maxUnavailable 1 selecting app=slowapp" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n heal get pdb slowapp -o json | jq -e '.spec.maxUnavailable==1 and .spec.selector.matchLabels.app==\"slowapp\"'"

section "3: logger native sidecar"
check "shipper is an initContainer with restartPolicy Always" dep logger \
  'any(.spec.template.spec.initContainers[]?; .name=="shipper" and .restartPolicy=="Always")'
check "shipper is not a regular container" dep logger 'all(.spec.template.spec.containers[]; .name!="shipper")'
check "shipper mounts the log volume" dep logger \
  '.spec.template.spec.initContainers[] | select(.name=="shipper") | any(.volumeMounts[]?; .mountPath=="/var/log/app")'
check_eq "logger 1/1 available" 1 kcq -n heal get deploy logger -o 'jsonpath={.status.availableReplicas}'
check_match "kubectl logs -c shipper shows orders" 'order [0-9]+ processed' kc -n heal logs deploy/logger -c shipper --tail=5

section "4: Job report"
job() { kcq -n heal get job report -o json | jq -e "$1" >/dev/null; }
check "uploader is a native sidecar" job 'any(.spec.template.spec.initContainers[]?; .name=="uploader" and .restartPolicy=="Always")'
check "backoffLimit 0" job '.spec.backoffLimit==0'
check "ttlSecondsAfterFinished 600" job '.spec.ttlSecondsAfterFinished==600'
check "Job Complete" job 'any(.status.conditions[]?; .type=="Complete" and .status=="True")'
check_match "report container wrote 'report done'" 'report done' bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n heal get job report -o json | jq -r '.spec.template.spec.containers[0].command | join(\" \")'"
finish
