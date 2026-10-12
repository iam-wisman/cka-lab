#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
get() { kc -n ts-net exec shopper -- wget -qO- -T 4 "http://$1" 2>/dev/null; }
svc() { kcq -n ts-net get svc "$1" -o json | jq -e "$2" >/dev/null; }

section "end to end from shopper"
check_eq "checkout" "checkout ok" get checkout
check_eq "payments" "payments ok" get payments
check_eq "inventory" "inventory ok" get inventory

section "how"
check "checkout Service selects app=checkout" svc checkout '.spec.selector=={"app":"checkout"}'
check "payments Service targets the container port (http/8080)" svc payments 'any(.spec.ports[]; .targetPort=="http" or .targetPort==8080)'
check "lockdown unchanged" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ts-net get networkpolicy lockdown -o json | jq -e '.spec.podSelector=={\"matchLabels\":{\"app\":\"inventory\"}} and .spec.policyTypes==[\"Ingress\"] and (.spec.ingress|not)'"
check "another pod in ts-net is still refused by inventory" bash -c \
  "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ts-net run grader-probe-\$RANDOM --rm -i --restart=Never --image=busybox:1.37 -q -- wget -qO- -T 4 http://inventory.ts-net.svc.cka.local >/dev/null 2>&1"
check_eq "shopper dnsPolicy ClusterFirst" ClusterFirst kcq -n ts-net get pod shopper -o 'jsonpath={.spec.dnsPolicy}'
check "CoreDNS serves cka.local again" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -Eq '^\s*kubernetes\s+cka\.local\b'"
check "a fresh pod resolves kubernetes.default.svc.cka.local" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ts-net run grader-dns-\$RANDOM --rm -i --restart=Never --image=busybox:1.37 -q -- nslookup kubernetes.default.svc.cka.local 2>/dev/null | grep -q '10.112.0.1'"
finish
