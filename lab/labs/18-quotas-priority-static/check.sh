#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
q() { kcq -n team-a get "$1" -o json | jq -e "$2" >/dev/null; }

section "A: quota and limits"
check "quota compute: requests 2/2Gi, limits 4/4Gi" q resourcequota/compute \
  '.spec.hard["requests.cpu"]=="2" and .spec.hard["requests.memory"]=="2Gi" and .spec.hard["limits.cpu"]=="4" and .spec.hard["limits.memory"]=="4Gi"'
check "quota compute: pods 10, deployments 3, nodeports 0" q resourcequota/compute \
  '.spec.hard.pods=="10" and .spec.hard["count/deployments.apps"]=="3" and .spec.hard["services.nodeports"]=="0"'
check "LimitRange container-defaults" q limitrange/container-defaults '
  any(.spec.limits[]; .type=="Container"
    and .defaultRequest.cpu=="100m" and .defaultRequest.memory=="128Mi"
    and .default.cpu=="500m" and .default.memory=="256Mi"
    and .max.cpu=="1" and .max.memory=="1Gi")'
check "burst Deployment has no resources in its own spec" q deploy/burst '.spec.template.spec.containers[0].resources == {} or (.spec.template.spec.containers[0].resources|not)'
check_eq "burst: 3/3 available" "3 3" kcq -n team-a get deploy burst -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'
check "burst pods got the defaults (100m/128Mi, 500m/256Mi)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n team-a get pod -l app=burst -o json | jq -e '(.items|length)==3 and all(.items[]; .spec.containers[0].resources == {\"requests\":{\"cpu\":\"100m\",\"memory\":\"128Mi\"},\"limits\":{\"cpu\":\"500m\",\"memory\":\"256Mi\"}})'"
check "NodePort service rejected" bash -c "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n team-a create service nodeport grader-probe --tcp=80 --dry-run=server >/dev/null 2>&1"
check "pod with a 2-CPU limit rejected" bash -c "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n team-a run grader-big --image=busybox:1.37 --dry-run=server --overrides='{\"spec\":{\"containers\":[{\"name\":\"grader-big\",\"image\":\"busybox:1.37\",\"resources\":{\"limits\":{\"cpu\":\"2\"}}}]}}' >/dev/null 2>&1"

section "B: priority"
check "critical-batch: 1000000, PreemptLowerPriority, not default" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get priorityclass critical-batch -o json | jq -e '.value==1000000 and (.preemptionPolicy // \"PreemptLowerPriority\")==\"PreemptLowerPriority\" and (.globalDefault // false)==false'"
check "best-effort-batch: -10, Never preempts" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get priorityclass best-effort-batch -o json | jq -e '.value==-10 and .preemptionPolicy==\"Never\"'"
check_eq "ingest: Running with critical-batch, priority 1000000" "Running critical-batch 1000000" \
  kcq -n team-a get pod ingest -o 'jsonpath={.status.phase} {.spec.priorityClassName} {.spec.priority}'

section "C: static pod"
real=$(on worker1 sed -n 's/^staticPodPath: *//p' /var/lib/kubelet/config.yaml)
check_eq "answers/18-static-path.txt" "${real:-<unreadable>}" bash -c "sed 's:/*$::' ~/answers/18-static-path.txt"
check "a manifest for static-web in that directory on worker1" on worker1 bash -c "grep -lqs 'name: static-web' ${real:-/nonexistent}/*.yaml"
check_eq "mirror pod default/static-web-worker1 Running" Running kcq get pod static-web-worker1 -o 'jsonpath={.status.phase}'
check_eq "mirror pod is owned by Node worker1" "Node worker1" kcq get pod static-web-worker1 -o 'jsonpath={.metadata.ownerReferences[0].kind} {.metadata.ownerReferences[0].name}'
finish
