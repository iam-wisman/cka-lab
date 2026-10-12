#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
t=$(helm_release traefik traefik)
CA=$LAB_STATE/cka-root-ca.crt
kcq -n cert-manager get secret cka-root-ca -o 'jsonpath={.data.ca\.crt}' | base64 -d >"$CA" 2>/dev/null
get() { curl -s --max-time 5 --cacert "$CA" --resolve shop.cka.lab:443:10.10.10.201 "https://shop.cka.lab$1"; }
ing() { kcq -n shop get ingress shop -o json | jq -e "$1" >/dev/null; }

section "controller"
check_eq "chart traefik 41.7.1" "traefik 41.7.1" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${t:-{\}}"
check "installed from ~/helm/traefik.yaml alone" python3 -c '
import sys, json, yaml
want = json.loads(sys.argv[1]).get("config", {}); have = yaml.safe_load(open(sys.argv[2])) or {}
sys.exit(0 if want and want == have else 1)' "${t:-{\}}" "$HOME/helm/traefik.yaml"
check_eq "2 replicas available" 2 kcq -n traefik get deploy traefik -o 'jsonpath={.status.availableReplicas}'
check "IngressClass traefik exists and is not default" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get ingressclass traefik -o json | jq -e '(.metadata.annotations[\"ingressclass.kubernetes.io/is-default-class\"] // \"false\") == \"false\"'"
check_eq "Service traefik has 10.10.10.201" 10.10.10.201 kcq -n traefik get svc traefik -o 'jsonpath={.status.loadBalancer.ingress[0].ip}'
check "Gateway API provider disabled" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n traefik get deploy traefik -o json | jq -e '[.spec.template.spec.containers[0].args[]] | (any(test(\"providers.kubernetesingress\"; \"i\"))) and (all(test(\"providers.kubernetesgateway\"; \"i\") | not))'"
check_match "http://shop.cka.lab redirects permanently to https" '^(301|308) https://shop\.cka\.lab' \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 --resolve shop.cka.lab:80:10.10.10.201 http://shop.cka.lab/api

section "Ingress shop"
check "class traefik, host shop.cka.lab" ing '.spec.ingressClassName=="traefik" and any(.spec.rules[]; .host=="shop.cka.lab")'
check "/api Prefix -> api" ing 'any(.spec.rules[].http.paths[]; .path=="/api" and .pathType=="Prefix" and .backend.service.name=="api")'
check "/static Exact -> static" ing 'any(.spec.rules[].http.paths[]; .path=="/static" and .pathType=="Exact" and .backend.service.name=="static")'
check "defaultBackend -> fallback" ing '.spec.defaultBackend.service.name=="fallback"'
check "TLS shop.cka.lab -> Secret shop-tls" ing 'any(.spec.tls[]; (.hosts|index("shop.cka.lab")) and .secretName=="shop-tls")'
check "cert requested through the Ingress (cert-manager.io/cluster-issuer: cka-ca)" ing '.metadata.annotations["cert-manager.io/cluster-issuer"]=="cka-ca"'
check "no hand-written Certificate (it's owned by the Ingress)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n shop get certificate shop-tls -o json | jq -e 'any(.metadata.ownerReferences[]?; .kind==\"Ingress\" and .name==\"shop\")'"

section "traffic (TLS verified against the CKA root CA)"
check_eq "/api/orders -> api" api get /api/orders
check_eq "/static -> static" static get /static
check_eq "/static/x -> fallback" fallback get /static/x
check_eq "/apiv2 -> fallback (Prefix matches whole path elements)" fallback get /apiv2
check "served certificate is shop-tls, issued by CKA Lab Root CA" bash -c \
  "echo | openssl s_client -connect 10.10.10.201:443 -servername shop.cka.lab -CAfile $CA 2>/dev/null | grep -q 'Verify return code: 0 (ok)'"
check "~/cka-root-ca.crt exported" bash -c "cmp -s ~/cka-root-ca.crt $CA"
finish
