#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster

for n in worker1 worker2; do
  section "$n"
  check_eq "$n Ready" True kcq get node "$n" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
  check_eq "$n is the original Node object" "$(cat "$LAB_STATE/lab27-$n-uid" 2>/dev/null || echo '<run lab start 27>')" kcq get node "$n" -o 'jsonpath={.metadata.uid}'
  check "kubelet enabled and active" on "$n" bash -c 'systemctl is-enabled -q kubelet && systemctl is-active -q kubelet'
  check "containerd enabled and active" on "$n" bash -c 'systemctl is-enabled -q containerd && systemctl is-active -q containerd'
  check "kubelet uses containerd's socket" on "$n" bash -c "grep -Eq '^containerRuntimeEndpoint: *\"?unix:///(var/)?run/containerd/containerd.sock\"?\s*$' /var/lib/kubelet/config.yaml"
  check "swap off now" on "$n" bash -c '[[ -z $(tail -n +2 /proc/swaps) ]]'
  check "no active swap entry in /etc/fstab" on "$n" bash -c '! grep -Ev "^\s*#" /etc/fstab | awk "\$3==\"swap\"" | grep -q .'
  check "kubelet.conf points at https://k8s-api.cka.lab:6443" on "$n" grep -q 'server: https://k8s-api.cka.lab:6443$' /etc/kubernetes/kubelet.conf
  pod=$(kcq -n kube-system get pod -l k8s-app=kube-proxy --field-selector "spec.nodeName=$n" -o 'jsonpath={.items[0].metadata.name}')
  check "kube-proxy on $n Running" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod ${pod:-none} -o jsonpath='{.status.phase}') == Running ]]"
done
finish
