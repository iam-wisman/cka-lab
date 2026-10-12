#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
CA=$LAB_STATE/cka-root-ca.crt
kcq -n cert-manager get secret cka-root-ca -o 'jsonpath={.data.ca\.crt}' | base64 -d >"$CA" 2>/dev/null
check_eq "https://docs.cka.lab/ (TLS verified)" "docs home" curl -s --max-time 5 --cacert "$CA" --resolve docs.cka.lab:443:10.10.10.201 https://docs.cka.lab/
check_eq "Ingress docs uses class traefik" traefik kcq -n e2-t10 get ingress docs -o 'jsonpath={.spec.ingressClassName}'
finish
