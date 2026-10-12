#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
M=/etc/kubernetes/manifests
ans() { sed -n "s/^$1=//p" "$HOME/answers/28-faults.txt" 2>/dev/null | head -1; }
stable() {  # stable <component> <node>: Running, ready, and not restarted in the last 60s
  kcq -n kube-system get pod "$1-$2" -o json | jq -e '.status.phase=="Running" and all(.status.containerStatuses[]; .ready and ((.state.running.startedAt | fromdateiso8601) < (now - 60)))' >/dev/null
}

for cp in "${CONTROL_PLANES[@]}"; do
  section "$cp"
  for c in kube-apiserver kube-controller-manager kube-scheduler; do
    check "$c-$cp running and stable for 60s" stable "$c" "$cp"
  done
  check "only the 4 kubeadm manifests in $M" on "$cp" bash -c "[[ \$(ls $M | sort | paste -sd,) == etcd.yaml,kube-apiserver.yaml,kube-controller-manager.yaml,kube-scheduler.yaml ]]"
  check_eq "$cp UP in HAProxy" UP bash -c "curl -sf --max-time 5 'http://10.10.10.10:8404/stats;csv' | awk -F, '\$2==\"$cp\" {print \$18; exit}'"
done

section "manifests"
check "cp1 scheduler uses /etc/kubernetes/scheduler.conf" on cp1 grep -q -- '--kubeconfig=/etc/kubernetes/scheduler.conf' $M/kube-scheduler.yaml
check "cp2 apiserver uses etcd on 127.0.0.1:2379" on cp2 grep -q -- '--etcd-servers=https://127.0.0.1:2379' $M/kube-apiserver.yaml
check "cp3 controller-manager signs with pki/ca.key" on cp3 grep -q -- '--cluster-signing-key-file=/etc/kubernetes/pki/ca.key' $M/kube-controller-manager.yaml

section "answers"
check_eq "cp1" kube-scheduler ans cp1
check_eq "cp2" kube-apiserver ans cp2
check_eq "cp3" kube-controller-manager ans cp3
finish
