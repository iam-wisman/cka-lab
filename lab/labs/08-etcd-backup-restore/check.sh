#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster

running=$(kcq -n kube-system get pod etcd-cp1 -o 'jsonpath={.spec.containers[0].image}' | sed 's/.*://; s/-[0-9]*$//')
etcd_json() {
  kc -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://10.10.10.11:2379,https://10.10.10.12:2379,https://10.10.10.13:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@" -w json 2>/dev/null
}

section "tools on cp1"
for t in etcdctl etcdutl; do
  check_match "$t in /usr/local/bin at v$running" "^$t version: ${running//./\\.}$" on cp1 bash -c "/usr/local/bin/$t version | head -1"
done

section "backup"
check "snapshot cp1:/var/backups/etcd/ledger.db passes etcdutl status" on cp1 /usr/local/bin/etcdutl snapshot status /var/backups/etcd/ledger.db
check "ledger.status holds the status table" on cp1 grep -Eq '^\| *HASH *\| *REVISION' /var/backups/etcd/ledger.status
local_sum=$(sha256sum "$HOME/backups/ledger.db" 2>/dev/null | cut -d' ' -f1)
node_sum=$(on cp1 sha256sum /var/backups/etcd/ledger.db 2>/dev/null | cut -d' ' -f1)
check "off-node copy ~/backups/ledger.db is identical" test -n "$local_sum" -a "$local_sum" = "$node_sum"
check "the disaster was triggered (lab start 08 disaster)" test -s "$LAB_STATE/lab08-disaster"

section "restore"
check_eq "ConfigMap ledger/accounts is the original object" "$(cat "$LAB_STATE/lab08-accounts-uid" 2>/dev/null)" \
  kcq -n ledger get cm accounts -o 'jsonpath={.metadata.uid}'
check_eq "Secret ledger/signing-key is the original object" "$(cat "$LAB_STATE/lab08-secret-uid" 2>/dev/null)" \
  kcq -n ledger get secret signing-key -o 'jsonpath={.metadata.uid}'
check_eq "accounts data intact" "1520.40 88.00 40210.99" kcq -n ledger get cm accounts -o 'jsonpath={.data.alice} {.data.bob} {.data.carol}'
check "ConfigMap ledger/journal restored" kc -n ledger get cm journal
check "namespace intruder is gone" bash -c "test -s $LAB_STATE/lab08-disaster && ! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get ns intruder >/dev/null 2>&1"
old_id=$(cat "$LAB_STATE/lab08-cluster-id" 2>/dev/null)
new_id=$(etcd_json endpoint status | jq -r '.[0].Status.header.cluster_id' 2>/dev/null)
check "etcd is a new cluster (cluster ID changed: a real restore)" bash -c "[[ -n '$old_id' && -n '$new_id' && '$old_id' != '$new_id' ]]"

section "etcd health"
member_names() { etcd_json member list | jq -r '[.members[].name] | sort | join(" ")'; }
all_healthy() { etcd_json endpoint health | jq -e 'length == 3 and all(.[]; .health == true)'; }
check_eq "3 members: cp1 cp2 cp3" "cp1 cp2 cp3" member_names
check "all 3 endpoints healthy" all_healthy
for cp in "${CONTROL_PLANES[@]}"; do
  check "$cp etcd data dir is /var/lib/etcd-from-backup" on "$cp" bash -c \
    "python3 -c 'import sys, yaml
m = yaml.safe_load(open(\"/etc/kubernetes/manifests/etcd.yaml\"))
paths = [v[\"hostPath\"][\"path\"].rstrip(\"/\") for v in m[\"spec\"][\"volumes\"] if \"hostPath\" in v]
sys.exit(0 if \"/var/lib/etcd-from-backup\" in paths else 1)' && test -d /var/lib/etcd-from-backup/member"
done

section "cluster"
for n in "${K8S_NODES[@]}"; do
  check_eq "$n Ready" True kcq get node "$n" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
done
for c in kube-apiserver kube-controller-manager kube-scheduler; do
  check "$c running on all control planes" bash -c \
    "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod -l component=$c -o json | jq '[.items[] | select(.status.phase==\"Running\")] | length') == 3 ]]"
done

finish
