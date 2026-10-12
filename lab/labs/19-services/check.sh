#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
svc() { kcq -n svc get svc "$1" -o json | jq -e "$2" >/dev/null; }
cx() { kc -n svc exec client -- "$@" 2>/dev/null; }

section "1: ClusterIP api"
check "port 8080 -> targetPort http (by name)" svc api '.spec.type=="ClusterIP" and any(.spec.ports[]; .port==8080 and .targetPort=="http")'
check "selector app=api" svc api '.spec.selector.app=="api"'
check "sessionAffinity ClientIP, 600s" svc api '.spec.sessionAffinity=="ClientIP" and .spec.sessionAffinityConfig.clientIP.timeoutSeconds==600'
check_eq "client reaches api:8080" api cx wget -qO- -T 3 http://api:8080

section "2: NodePort api-public"
check "NodePort 30080 -> http" svc api-public '.spec.type=="NodePort" and any(.spec.ports[]; .nodePort==30080 and .targetPort=="http")'
check "externalTrafficPolicy Local" svc api-public '.spec.externalTrafficPolicy=="Local"'
node=$(kcq -n svc get pod -l app=api -o 'jsonpath={.items[0].spec.nodeName}')
check_eq "curl http://$node:30080 from jump" api curl -s --max-time 5 "http://$node:30080"

section "3: headless api-peers"
check "clusterIP None, publishNotReadyAddresses" svc api-peers '.spec.clusterIP=="None" and .spec.publishNotReadyAddresses==true and .spec.selector.app=="api"'
check_eq "DNS returns all 3 pod IPs" 3 bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n svc exec client -- nslookup api-peers.svc.svc.cka.local 2>/dev/null | grep -A10 '^Name:' | grep -c '^Address'"

section "4: legacy-dns"
check "no selector; ports dns-udp/53 UDP and dns-tcp/53 TCP" svc legacy-dns \
  '(.spec.selector|not) and any(.spec.ports[]; .name=="dns-udp" and .port==53 and .protocol=="UDP") and any(.spec.ports[]; .name=="dns-tcp" and .port==53 and .protocol=="TCP")'
check "an EndpointSlice labelled kubernetes.io/service-name=legacy-dns -> 10.10.10.10" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n svc get endpointslices -l kubernetes.io/service-name=legacy-dns -o json | jq -e 'any(.items[]; .addressType==\"IPv4\" and any(.endpoints[]; .addresses|index(\"10.10.10.10\")) and any(.ports[]; .name==\"dns-udp\" and .port==53 and .protocol==\"UDP\") and any(.ports[]; .name==\"dns-tcp\" and .port==53 and .protocol==\"TCP\"))'"
check "no hand-written legacy Endpoints object (uses EndpointSlice)" bash -c \
  "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n svc get endpoints legacy-dns -o json 2>/dev/null | jq -e '.subsets | length > 0' >/dev/null"
check_match "nslookup db.corp.internal legacy-dns -> 10.10.10.30" 'Address:? *10\.10\.10\.30' cx nslookup db.corp.internal legacy-dns

section "5: ExternalName docs"
check "ExternalName kubernetes.io" svc docs '.spec.type=="ExternalName" and .spec.externalName=="kubernetes.io"'
finish
