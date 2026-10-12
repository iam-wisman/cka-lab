#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
CA=$LAB_STATE/cka-root-ca.crt
kcq -n cert-manager get secret cka-root-ca -o 'jsonpath={.data.ca\.crt}' | base64 -d >"$CA" 2>/dev/null
eg=$(helm_release envoy-gateway-system eg)
https() { curl -s --max-time 5 --cacert "$CA" --resolve store.cka.lab:443:10.10.10.202 "${@:2}" "https://store.cka.lab$1"; }
gw() { kcq -n infra get gateway cka-gw -o json | jq -e "$1" >/dev/null; }
route() { kcq -n "$1" get httproute "$2" -o json | jq -e "$3" >/dev/null; }

section "controller and class"
check_eq "chart gateway-helm v1.9.2" "gateway-helm v1.9.2" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${eg:-{\}}"
check "GatewayClass eg -> Envoy Gateway, Accepted" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get gatewayclass eg -o json | jq -e '.spec.controllerName==\"gateway.envoyproxy.io/gatewayclass-controller\" and any(.status.conditions[]; .type==\"Accepted\" and .status==\"True\")'"
check_eq "Certificate infra/store-gw-tls Ready" True kcq -n infra get certificate store-gw-tls -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'

section "Gateway cka-gw"
check "class eg, Programmed" gw '.spec.gatewayClassName=="eg" and any(.status.conditions[]; .type=="Programmed" and .status=="True")'
check "listener http: HTTP/80/store.cka.lab" gw 'any(.spec.listeners[]; .name=="http" and .protocol=="HTTP" and .port==80 and .hostname=="store.cka.lab")'
check "listener https: HTTPS/443, Terminate with store-gw-tls" gw \
  'any(.spec.listeners[]; .name=="https" and .protocol=="HTTPS" and .port==443 and .hostname=="store.cka.lab" and ((.tls.mode // "Terminate")=="Terminate") and any(.tls.certificateRefs[]; .name=="store-gw-tls"))'
check "both listeners: routes only from namespaces labelled gateway-access=true" gw \
  'all(.spec.listeners[]; .allowedRoutes.namespaces.from=="Selector" and .allowedRoutes.namespaces.selector.matchLabels["gateway-access"]=="true")'
check "10.10.10.202 requested in the Gateway spec (infrastructure annotation or addresses)" gw \
  '(.spec.infrastructure.annotations["metallb.io/loadBalancerIPs"]=="10.10.10.202") or any(.spec.addresses[]?; .value=="10.10.10.202")'
check_eq "Gateway status address 10.10.10.202" 10.10.10.202 kcq -n infra get gateway cka-gw -o 'jsonpath={.status.addresses[0].value}'

section "routes"
check "store-redirect attached to sectionName http only" route store store-redirect '[.spec.parentRefs[] | .sectionName] == ["http"]'
check "store attached to sectionName https only" route store store '[.spec.parentRefs[] | .sectionName] == ["https"]'
check "store route Accepted with all refs resolved" route store store \
  'any(.status.parents[]; any(.conditions[]; .type=="Accepted" and .status=="True") and any(.conditions[]; .type=="ResolvedRefs" and .status=="True"))'
check "ReferenceGrant in legacy: HTTPRoute from store -> Service" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n legacy get referencegrants -o json | jq -e 'any(.items[]; any(.spec.from[]; .kind==\"HTTPRoute\" and .namespace==\"store\") and any(.spec.to[]; .kind==\"Service\" and ((.group // \"\")==\"\")))'"
check "rogue/admin NOT accepted by cka-gw" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n rogue get httproute admin -o json | jq -e '.status.parents | length > 0 and all(.[]; any(.conditions[]; .type==\"Accepted\" and .status==\"False\"))'"

section "traffic"
check_match "http -> 301 https" '^301 https://store\.cka\.lab' curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 --resolve store.cka.lab:80:10.10.10.202 http://store.cka.lab/x
canary() { local i; for i in 1 2 3 4 5 6; do [[ $(https / -H 'x-canary: true') == v2 ]] || return 1; done; }
check "x-canary: true -> always v2 (6/6)" canary
check_match "/old/cart -> 301 /new/cart" '^301 https://store\.cka\.lab/new/cart$' https /old/cart -o /dev/null -w '%{http_code} %{redirect_url}'
check_eq "/legacy -> legacy (cross-namespace)" legacy https /legacy
check "/admin is not served by rogue" bash -c "[[ \$(curl -s --max-time 5 --cacert $CA --resolve store.cka.lab:443:10.10.10.202 https://store.cka.lab/admin) != pwned ]]"
split=$(for i in $(seq 1 100); do https /; echo; done | sort | uniq -c | awk '{print $2"="$1}' | paste -sd' ')
v2=$(grep -o 'v2=[0-9]*' <<<"$split" | cut -d= -f2)
check "weighted split ~80/20 over 100 requests ($split)" bash -c "(( ${v2:-0} >= 8 && ${v2:-0} <= 35 )) && grep -q 'v1=' <<<'$split'"
finish
