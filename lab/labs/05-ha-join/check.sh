#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster

node_field() { kcq get node "$1" -o "jsonpath=$2"; }

section "nodes"
for n in "${K8S_NODES[@]}"; do
  check_eq "$n Ready" True node_field "$n" '{.status.conditions[?(@.type=="Ready")].status}'
done
for n in cp2 cp3; do
  check "$n is a control plane (role label)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node $n -o json | jq -e '.metadata.labels | has(\"node-role.kubernetes.io/control-plane\")'"
done
for n in "${CONTROL_PLANES[@]}"; do
  check "$n keeps the control-plane NoSchedule taint" bash -c \
    "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node $n -o json | jq -e 'any(.spec.taints[]?; .key==\"node-role.kubernetes.io/control-plane\" and .effect==\"NoSchedule\")'"
done
check "kube-apiserver on cp2 advertises 10.10.10.12" on cp2 grep -q -- '--advertise-address=10.10.10.12' /etc/kubernetes/manifests/kube-apiserver.yaml
check "kube-apiserver on cp3 advertises 10.10.10.13" on cp3 grep -q -- '--advertise-address=10.10.10.13' /etc/kubernetes/manifests/kube-apiserver.yaml
for n in "${WORKERS[@]}"; do
  check "$n has no control-plane components" on "$n" bash -c '! ls /etc/kubernetes/manifests/*.yaml >/dev/null 2>&1'
done

section "labels"
declare -A zone=([cp1]=zone-a [cp2]=zone-b [cp3]=zone-c [worker1]=zone-a [worker2]=zone-b)
for n in "${K8S_NODES[@]}"; do
  check_eq "$n zone ${zone[$n]}" "${zone[$n]}" node_field "$n" '{.metadata.labels.topology\.kubernetes\.io/zone}'
done
for n in "${WORKERS[@]}"; do
  check "$n has node-role.kubernetes.io/worker=\"\"" bash -c \
    "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node $n -o json | jq -e '.metadata.labels[\"node-role.kubernetes.io/worker\"] == \"\"'"
done
for n in "${CONTROL_PLANES[@]}"; do
  check "$n has no worker role label" bash -c \
    "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node $n -o json | jq -e '.metadata.labels | has(\"node-role.kubernetes.io/worker\") | not'"
done

section "certificates"
for n in "${K8S_NODES[@]}"; do
  pod=$(kcq -n kube-system get pod -l k8s-app=kube-proxy --field-selector "spec.nodeName=$n" -o 'jsonpath={.items[0].metadata.name}')
  check "kubectl logs works for a pod on $n" kc -n kube-system logs "${pod:-none}" --tail=1
done
forged=$(cat "$LAB_STATE/lab05-forged-csr" 2>/dev/null)
if [[ -z $forged ]]; then
  check "forged CSR denied (run 'lab start 05' first)" false
elif kc get csr "$forged" >/dev/null 2>&1; then
  check_eq "forged CSR $forged (requested by kubernetes-admin, extra SANs) is Denied" Denied \
    kcq get csr "$forged" -o 'jsonpath={.status.conditions[0].type}'
else
  check "forged CSR $forged denied (it's gone: CSRs are garbage-collected an hour after a decision. Re-run 'lab start 05' and deny the new one)" false
fi

section "etcd"
etcdctl() {
  kc -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key "$@"
}
members=$(etcdctl member list -w json 2>/dev/null)
check_eq "3 etcd members: cp1 cp2 cp3" "cp1 cp2 cp3" bash -c "jq -r '[.members[].name] | sort | join(\" \")' <<<'$members'"
check "no learners" bash -c "jq -e 'all(.members[]; (.isLearner // false) == false)' <<<'$members'"
check "all members healthy" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system exec etcd-cp1 -- etcdctl --endpoints=https://10.10.10.11:2379,https://10.10.10.12:2379,https://10.10.10.13:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint health -w json | jq -e 'length == 3 and all(.[]; .health == true)'"

section "load balancer"
for n in "${CONTROL_PLANES[@]}"; do
  check_eq "$n UP in HAProxy" UP bash -c "curl -sf --max-time 5 'http://10.10.10.10:8404/stats;csv' | awk -F, '\$2==\"$n\" {print \$18; exit}'"
done

section "snapshot"
check "snapshot cluster-ready exists on every lab VM" bash -c \
  "lab snapshots | awk 'NF {print \$1, (/cluster-ready/ ? \"y\" : \"n\")}' | grep -q ' y' && ! lab snapshots | awk 'NF' | grep -vq cluster-ready"

finish
