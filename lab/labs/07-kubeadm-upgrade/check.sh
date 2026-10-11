#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

V=1.35.9
need_cluster

# What kubeadm v1.35.9 itself expects for each image.
images=$(on cp1 kubeadm config images list --kubernetes-version "v$V" 2>/dev/null)
want() { grep "/$1:" <<<"$images" | head -1; }

section "control plane"
check_eq "kubeadm-config kubernetesVersion v$V" "v$V" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)[\"kubernetesVersion\"])'"
for cp in "${CONTROL_PLANES[@]}"; do
  for c in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    check_eq "$cp $c image $(want "$c" | sed 's|.*/||')" "$(want "$c")" \
      kcq -n kube-system get pod "$c-$cp" -o 'jsonpath={.spec.containers[0].image}'
  done
done
check_eq "kube-proxy image $(want kube-proxy | sed 's|.*/||')" "$(want kube-proxy)" \
  kcq -n kube-system get ds kube-proxy -o 'jsonpath={.spec.template.spec.containers[0].image}'
check_eq "CoreDNS image $(want coredns | sed 's|.*/||')" "$(want coredns)" \
  kcq -n kube-system get deploy coredns -o 'jsonpath={.spec.template.spec.containers[0].image}'

section "nodes"
for n in "${K8S_NODES[@]}"; do
  check_eq "$n kubelet v$V" "v$V" kcq get node "$n" -o 'jsonpath={.status.nodeInfo.kubeletVersion}'
  check_eq "$n Ready" True kcq get node "$n" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
  check_eq "$n schedulable" "" kcq get node "$n" -o 'jsonpath={.spec.unschedulable}'
  check "$n packages at $V and held" on "$n" bash -c "
    for p in kubeadm kubelet kubectl; do
      [[ \$(dpkg-query -W -f='\${Version}' \$p) == $V-* ]] && apt-mark showhold | grep -qx \$p || exit 1
    done"
  check "$n uses the pkgs.k8s.io v1.35 channel" on "$n" bash -c \
    "grep -rhqs 'pkgs.k8s.io/core:/stable:/v1.35/deb' /etc/apt/sources.list.d/ && ! grep -rhqs 'pkgs.k8s.io/core:/stable:/v1.34/deb' /etc/apt/sources.list.d/"
  check_eq "$n containerd sandbox image $(want pause | sed 's|.*/||')" "$(want pause)" on "$n" bash -c \
    "containerd config dump 2>/dev/null | sed -n \"/pinned_images\]/,/^\s*\[/p\" | sed -n \"s/^\s*sandbox = '\(.*\)'/\1/p\""
done

section "jump"
check "kubectl $V held on jump" bash -c "[[ \$(dpkg-query -W -f='\${Version}' kubectl) == $V-* ]] && apt-mark showhold | grep -qx kubectl"

section "uptime workloads"
check_eq "PDB uptime/frontend is the original object" "$(cat "$LAB_STATE/lab07-pdb-uid" 2>/dev/null || echo '<run lab start 07>')" \
  kcq -n uptime get pdb frontend -o 'jsonpath={.metadata.uid}'
check_eq "PDB spec unchanged (minAvailable 4, generation 1)" "4 1" \
  kcq -n uptime get pdb frontend -o 'jsonpath={.spec.minAvailable} {.metadata.generation}'
check_eq "frontend: 4 replicas, 4 available" "4 4" \
  kcq -n uptime get deploy frontend -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'
check "node-agent DaemonSet fully available" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n uptime get ds node-agent -o json | jq -e '.status.desiredNumberScheduled > 0 and .status.numberAvailable == .status.desiredNumberScheduled and .status.updatedNumberScheduled == .status.desiredNumberScheduled'"
check_eq "cache: 2 available" 2 kcq -n uptime get deploy cache -o 'jsonpath={.status.availableReplicas}'

finish
