#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
CA=$LAB_STATE/cka-root-ca.crt
kcq -n cert-manager get secret cka-root-ca -o 'jsonpath={.data.ca\.crt}' | base64 -d >"$CA" 2>/dev/null
check_eq "https://store.cka.lab/promo/x -> promo" promo curl -s --max-time 5 --cacert "$CA" --resolve store.cka.lab:443:10.10.10.202 https://store.cka.lab/promo/x
check "HTTPRoute e1-t10/promo attached to the https listener" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n e1-t10 get httproute promo -o json | jq -e 'any(.spec.parentRefs[]; .name==\"cka-gw\" and .namespace==\"infra\" and .sectionName==\"https\") and any(.status.parents[]; any(.conditions[]; .type==\"Accepted\" and .status==\"True\"))'"
check_eq "Gateway unchanged" "$(cat $LAB_STATE/exam1-t10-gwgen 2>/dev/null)" kcq -n infra get gateway cka-gw -o 'jsonpath={.metadata.generation}'
finish
