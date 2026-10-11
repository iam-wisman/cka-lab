#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
nodes_of() { kcq -n sched get pod -l "app=$1" -o json | jq -r '[.items[] | select(.status.phase=="Running") | .spec.nodeName] | sort | join(" ")'; }
zone_of() { kcq get node "$1" -o 'jsonpath={.metadata.labels.topology\.kubernetes\.io/zone}'; }

section "1: analytics"
check_eq "2 running pods, both on worker2" "worker2 worker2" nodes_of analytics
check "uses node affinity/selector for worker2 (not just a toleration)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get deploy analytics -o json | jq -e '.spec.template.spec | (.nodeSelector // {} | length > 0) or (.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution != null)'"
check "tolerates dedicated=analytics:NoSchedule" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get deploy analytics -o json | jq -e 'any(.spec.template.spec.tolerations[]?; .key==\"dedicated\" and (.value==\"analytics\" or .operator==\"Exists\") and (.effect==\"NoSchedule\" or (.effect|not)))'"

section "2: edge"
edge=$(nodes_of edge)
check_eq "6 running" 6 bash -c "wc -w <<<'$edge'"
check_eq "2 per zone (zone-a zone-b zone-c)" "2 2 2" bash -c \
  "for z in zone-a zone-b zone-c; do c=0; for n in $edge; do [[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node \$n -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}') == \$z ]] && c=\$((c+1)); done; printf '%s ' \$c; done | sed 's/ \$//'"
check "none on worker2" bash -c "! grep -qw worker2 <<<'$edge'"
check "zone spread is strict (DoNotSchedule, maxSkew 1)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get deploy edge -o json | jq -e 'any(.spec.template.spec.topologySpreadConstraints[]?; .topologyKey==\"topology.kubernetes.io/zone\" and .maxSkew==1 and .whenUnsatisfiable==\"DoNotSchedule\")'"
check "hostname spread is soft (ScheduleAnyway) or preferred anti-affinity" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get deploy edge -o json | jq -e '.spec.template.spec | any(.topologySpreadConstraints[]?; .topologyKey==\"kubernetes.io/hostname\" and .whenUnsatisfiable==\"ScheduleAnyway\") or (.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution != null)'"

section "3: fast-io"
check_eq "worker1 labelled disktype=ssd" ssd kcq get node worker1 -o 'jsonpath={.metadata.labels.disktype}'
check_eq "fast-io running on worker1" "Running worker1" kcq -n sched get pod fast-io -o 'jsonpath={.status.phase} {.spec.nodeName}'
check "required: zone In [zone-a, zone-b]" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get pod fast-io -o json | jq -e 'any(.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[]; .key==\"topology.kubernetes.io/zone\" and .operator==\"In\" and (.values|sort)==[\"zone-a\",\"zone-b\"])'"
check "preferred: disktype=ssd weight 80" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get pod fast-io -o json | jq -e 'any(.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[]; .weight==80 and any(.preference.matchExpressions[]; .key==\"disktype\" and (.values|index(\"ssd\"))))'"

section "4: cache"
cache=$(nodes_of cache)
two_apart() { set -- $cache; [[ $# == 2 && $1 != "$2" ]]; }
check "2 running on different nodes" two_apart
check "each cache pod shares a node with an edge pod" bash -c "for n in $cache; do grep -qw \$n <<<'$edge' || exit 1; done; [[ -n '$cache' ]]"
check "uses required podAffinity to edge and podAntiAffinity to cache" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get deploy cache -o json | jq -e '.spec.template.spec.affinity | (.podAffinity.requiredDuringSchedulingIgnoredDuringExecution != null) and (.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution != null)'"

section "5: manual"
check_eq "manual Running on cp3" "Running cp3" kcq -n sched get pod manual -o 'jsonpath={.status.phase} {.spec.nodeName}'
check "bypassed the scheduler (nodeName set in the spec, no scheduler event)" bash -c \
  "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n sched get events --field-selector involvedObject.name=manual,reason=Scheduled -o name | grep -q ."
finish
