#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
m=$(helm_release metallb-system metallb)
ip() { kcq -n lb get svc "$1" -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'; }
pool() { kcq -n metallb-system get ipaddresspools.metallb.io "$1" -o json | jq -e "$2" >/dev/null; }
in_range() { local a=${1##*.}; [[ $1 == 10.10.10.* ]] && (( a >= $2 && a <= $3 )); }

section "install"
check_eq "chart metallb 0.16.1" "metallb 0.16.1" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${m:-{\}}"
check_eq "namespace metallb-system enforces privileged PSA" privileged kcq get ns metallb-system -o 'jsonpath={.metadata.labels.pod-security\.kubernetes\.io/enforce}'
check "controller and speakers ready" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n metallb-system get ds,deploy -o json | jq -e '(.items|length)>=2 and all(.items[]; (.status.numberReady // .status.readyReplicas // 0) >= 1)'"

section "pools"
check "lab-pool 10.10.10.200-10.10.10.220, autoAssign" pool lab-pool '(.spec.addresses == ["10.10.10.200-10.10.10.220"]) and ((.spec.autoAssign // true) == true)'
check "reserved 10.10.10.230-10.10.10.235, autoAssign false" pool reserved '(.spec.addresses == ["10.10.10.230-10.10.10.235"]) and .spec.autoAssign == false'
check "L2Advertisement covering both pools" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n metallb-system get l2advertisements.metallb.io -o json | jq -e '
    [.items[] | (.spec.ipAddressPools // [\"*\"])[]] as \$p | ((\$p|index(\"*\")) or ((\$p|index(\"lab-pool\")) and (\$p|index(\"reserved\"))))'"

section "services"
check_eq "web has 10.10.10.205" 10.10.10.205 ip web
check_eq "curl http://10.10.10.205 from jump" "hello from lb" curl -s --max-time 5 http://10.10.10.205
check "web-reserved got an address in 230-235" in_range "$(ip web-reserved)" 230 235
check "web-auto got an address in 200-220" in_range "$(ip web-auto)" 200 220
check "web-auto has no MetalLB annotations" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n lb get svc web-auto -o json | jq -e '[.metadata.annotations // {} | keys[] | select(startswith(\"metallb.io/\"))] | length == 0'"
finish
