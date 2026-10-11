#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
D=(-n rollout get deploy web)
f() { kcq "${D[@]}" -o "jsonpath=$1"; }
rs_json() { kcq -n rollout get rs -l app=web -o json; }
rsq() { rs_json | jq -e "$1" >/dev/null; }      # rsq <jq test over the ReplicaSet list>

section "strategy"
check_eq "maxSurge 2, maxUnavailable 0" "2 0" f '{.spec.strategy.rollingUpdate.maxSurge} {.spec.strategy.rollingUpdate.maxUnavailable}'
check_eq "minReadySeconds 5" 5 f '{.spec.minReadySeconds}'
check_eq "progressDeadlineSeconds 60" 60 f '{.spec.progressDeadlineSeconds}'
check_eq "revisionHistoryLimit 4" 4 f '{.spec.revisionHistoryLimit}'

section "history"
bad_rs=$(rs_json | jq -r '.items[] | select(.spec.template.spec.containers[0].image=="nginx:1.99-alpine")')
check "the 1.99 ReplicaSet still exists in history" test -n "$bad_rs"
check_eq "bad release change-cause recorded" "bad release" jq -r '.metadata.annotations["kubernetes.io/change-cause"]' <<<"${bad_rs:-{\}}"
check_eq "answers/12-bad-revision.txt holds its revision" "$(jq -r '.metadata.annotations["deployment.kubernetes.io/revision"]' <<<"${bad_rs:-{\}}")" cat "$HOME/answers/12-bad-revision.txt"
check_eq "bad ReplicaSet scaled to 0" 0 jq -r '.spec.replicas' <<<"${bad_rs:-{\"spec\":{\"replicas\":-1}}}"
check "a 1.27 revision with change-cause 'upgrade to 1.27' and no env exists" rsq \
  'any(.items[]; .spec.template.spec.containers[0].image=="nginx:1.27-alpine" and (.spec.template.spec.containers[0].env|not) and .metadata.annotations["kubernetes.io/change-cause"]=="upgrade to 1.27")'
check "no revision has the limits without RELEASE=blue (changes made while paused)" rsq \
  '[.items[] | select(.spec.template.spec.containers[0].resources.limits and ((.spec.template.spec.containers[0].env // []) | any(.name=="RELEASE") | not))] | length == 0'
check "no revision has RELEASE=blue without the limits" rsq \
  '[.items[] | select(((.spec.template.spec.containers[0].env // []) | any(.name=="RELEASE")) and (.spec.template.spec.containers[0].resources.limits | not))] | length == 0'

section "current state"
check_eq "image nginx:1.27-alpine" nginx:1.27-alpine f '{.spec.template.spec.containers[0].image}'
check_eq "RELEASE=blue" blue f '{.spec.template.spec.containers[0].env[?(@.name=="RELEASE")].value}'
check_eq "limits 200m/128Mi, requests 50m/64Mi" "200m 128Mi 50m 64Mi" f '{.spec.template.spec.containers[0].resources.limits.cpu} {.spec.template.spec.containers[0].resources.limits.memory} {.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory}'
check_eq "change-cause tuning" tuning f '{.metadata.annotations.kubernetes\.io/change-cause}'
check_eq "not paused" "" f '{.spec.paused}'
check_eq "4 replicas updated and available" "4 4 4" f '{.spec.replicas} {.status.updatedReplicas} {.status.availableReplicas}'
check_eq "rollout Progressing=True (NewReplicaSetAvailable)" NewReplicaSetAvailable f '{.status.conditions[?(@.type=="Progressing")].reason}'
finish
