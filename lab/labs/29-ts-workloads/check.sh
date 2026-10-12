#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
d() { kcq -n ts-apps get deploy "$1" -o json | jq -e "$2" >/dev/null; }
avail() { d "$1" '.status.availableReplicas == .spec.replicas and .spec.replicas > 0 and .status.updatedReplicas == .spec.replicas'; }

for app in web worker cache db batch api crasher; do
  check "$app fully available" avail "$app"
done

section "constraints"
check "web image nginx:1.27-alpine" d web '.spec.template.spec.containers[0].image=="nginx:1.27-alpine"'
check_eq "ConfigMap worker-config untouched" "$(cat "$LAB_STATE/lab29-cm-rv" 2>/dev/null)" kcq -n ts-apps get cm worker-config -o 'jsonpath={.metadata.resourceVersion}'
check_match "worker sees the queue URL" 'consuming amqp://queue.ts-apps:5672 with 4 workers' kc -n ts-apps logs deploy/worker
check "cache runs on a worker node" bash -c \
  "n=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ts-apps get pod -l app=cache -o jsonpath='{.items[0].spec.nodeName}'); [[ \$n == worker1 || \$n == worker2 ]]"
check "cache is constrained to workers (not just lucky)" d cache \
  '(.spec.template.spec.nodeSelector // {} | has("node-role.kubernetes.io/worker")) or (.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution != null)'
check_eq "PVC db-data Bound via nfs-csi" "Bound nfs-csi" kcq -n ts-apps get pvc db-data -o 'jsonpath={.status.phase} {.spec.storageClassName}'
check "batch memory limit 128Mi, command unchanged" d batch \
  '.spec.template.spec.containers[0].resources.limits.memory=="128Mi" and (.spec.template.spec.containers[0].command | join(" ") | contains("60 * 1024 * 1024"))'
check "api still has a readiness probe, on port 8080/http" d api \
  '.spec.template.spec.containers[0].readinessProbe.httpGet.port as $p | ($p==8080 or $p=="http")'
check_eq "Service api answers 'api ok' in-cluster" "api ok" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ts-apps run grader-probe-\$RANDOM --rm -i --restart=Never --image=busybox:1.37 -q -- wget -qO- -T 5 http://api 2>/dev/null"
check "crasher runs sleep (image unchanged)" d crasher '.spec.template.spec.containers[0].command[0]=="sleep" and .spec.template.spec.containers[0].image=="busybox:1.37"'
finish
