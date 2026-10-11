#!/bin/bash
# Lab 08 setup.
#   lab start 08            create the data that must survive (namespace ledger)
#   lab start 08 disaster   after your backup: destroy ledger, plant an intruder
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$LAB_STATE"

case ${1:-} in
"")
  kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: ledger}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: accounts, namespace: ledger}
data: {alice: "1520.40", bob: "88.00", carol: "40210.99"}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: journal, namespace: ledger}
data: {"2026-10-01": "opening balances", "2026-10-09": "q3 close"}
---
apiVersion: v1
kind: Secret
metadata: {name: signing-key, namespace: ledger}
stringData: {key: "ledger-hmac-7f3a91"}
YAML
  # Remember identities: a restore brings these exact objects back; recreating them by hand can't.
  kc -n ledger get cm accounts -o jsonpath='{.metadata.uid}' >"$LAB_STATE/lab08-accounts-uid"
  kc -n ledger get secret signing-key -o jsonpath='{.metadata.uid}' >"$LAB_STATE/lab08-secret-uid"
  rm -f "$LAB_STATE/lab08-disaster" "$LAB_STATE/lab08-cluster-id"
  echo "Namespace ledger is ready. Back it up (task 2), then run: lab start 08 disaster"
  ;;
disaster)
  on cp1 test -s /var/backups/etcd/ledger.db || die "no snapshot at cp1:/var/backups/etcd/ledger.db yet. Back up first!"
  kc -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key endpoint status -w json |
    jq -r '.[0].Status.header.cluster_id' >"$LAB_STATE/lab08-cluster-id"
  kc delete namespace ledger --wait=true >/dev/null
  kc create namespace intruder >/dev/null
  kc -n intruder create configmap backdoor --from-literal=owner=mallory >/dev/null
  date -u +%FT%TZ >"$LAB_STATE/lab08-disaster"
  echo "Disaster: namespace ledger is gone and someone created namespace intruder. Restore etcd."
  ;;
*) die "unknown phase '$1' (use: lab start 08 [disaster])" ;;
esac
