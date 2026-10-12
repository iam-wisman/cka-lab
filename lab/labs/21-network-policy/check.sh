#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
# tcp <ns> <pod> <host> <port>: TCP connect from a pod within 3s
tcp() { kc -n "$1" exec "$2" -- nc -z -w 3 "$3" "$4" >/dev/null 2>&1; }
open_() { tcp "$@"; }
closed() { ! tcp "$@"; }
API=api.backend.svc.cka.local DB=postgres.db.svc.cka.local
dns() { kc -n "$1" exec "$2" -- timeout 6 nslookup kubernetes.default.svc.cka.local >/dev/null 2>&1; }

section "policy objects"
for ns in backend db; do
  check "$ns/default-deny selects all pods, Ingress+Egress, no rules" bash -c \
    "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $ns get networkpolicy default-deny -o json | jq -e '.spec.podSelector=={} and (.spec.policyTypes|sort)==[\"Egress\",\"Ingress\"] and (.spec.ingress|not) and (.spec.egress|not)'"
done

section "DNS"
check "backend/api can resolve names" dns backend api
check "db/postgres can resolve names" dns db postgres
check "backend/api can't reach a non-CoreDNS DNS server (10.10.10.10:53)" closed backend api 10.10.10.10 53

section "into api"
check "frontend/web -> api:80 allowed" open_ frontend web "$API" 80
check "frontend/other -> api:80 refused" closed frontend other "$API" 80
check "monitoring/web -> api:80 refused (app=web but wrong namespace)" closed monitoring web "$API" 80
check "monitoring/prom -> api:80 allowed" open_ monitoring prom "$API" 80

section "api <-> db"
check "backend/api -> postgres:5432 allowed" open_ backend api "$DB" 5432
check "frontend/web -> postgres:5432 refused" closed frontend web "$DB" 5432
check "monitoring/prom -> postgres:5432 refused" closed monitoring prom "$DB" 5432
check "postgres can't open connections out (-> api:80)" closed db postgres "$API" 80

section "egress to the lab network"
check "backend/api -> nfs (10.10.10.30):22 allowed" open_ backend api 10.10.10.30 22
check "backend/api -> jump (10.10.10.10):22 refused" closed backend api 10.10.10.10 22
check "backend/api -> internet (1.1.1.1:443) refused (only SSH to the lab net)" closed backend api 1.1.1.1 443
check "frontend/web -> internet (1.1.1.1:443) still allowed (frontend unrestricted)" open_ frontend web 1.1.1.1 443
finish
