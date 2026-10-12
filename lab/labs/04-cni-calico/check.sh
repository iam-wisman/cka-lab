#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster
rel=$(helm_release tigera-operator calico)
rq() { jq -r "$1" <<<"${rel:-{\}}" 2>/dev/null; }
pool() { kcq get installation default -o json | jq -r ".spec.calicoNetwork.ipPools[0]$1 // empty"; }

section "Helm"
check_match "helm 3 on jump" '^v3\.' bash -c 'helm version --short'
check "release calico deployed in tigera-operator" test -n "$rel"
check_eq "chart tigera-operator v3.32.2" "tigera-operator v3.32.2" rq '"\(.chart.metadata.name) \(.chart.metadata.version)"'
check "installed from ~/calico/values.yaml alone (release values == file, so no --set)" release_values_match tigera-operator calico "$HOME/calico/values.yaml"

check_eq "Calico CRDs at v3.32.2 (operator.tigera.io installations CRD present)" installations.operator.tigera.io \
  kcq get crd installations.operator.tigera.io -o 'jsonpath={.metadata.name}'

section "Installation / IP pool"
check "exactly one IPv4 pool in the Installation" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get installation default -o json | jq '.spec.calicoNetwork.ipPools | length') == 1 ]]"
check_eq "pool name default-ipv4-ippool" default-ipv4-ippool pool .name
check_eq "pool CIDR 172.16.0.0/16" 172.16.0.0/16 pool .cidr
check_eq "encapsulation VXLAN (always)" VXLAN pool .encapsulation
check_eq "natOutgoing Enabled" Enabled pool .natOutgoing
check_eq "blockSize 24" 24 pool .blockSize
check_eq "BGP disabled" Disabled bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get installation default -o jsonpath='{.spec.calicoNetwork.bgp}'"
check_eq "live IPPool CIDR is 172.16.0.0/16" 172.16.0.0/16 kcq get ippools.crd.projectcalico.org default-ipv4-ippool -o 'jsonpath={.spec.cidr}'
check_eq "live IPPool vxlanMode Always" Always kcq get ippools.crd.projectcalico.org default-ipv4-ippool -o 'jsonpath={.spec.vxlanMode}'

section "health"
check "all tigerastatus components Available" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get tigerastatus -o json | jq -e '(.items | length > 0) and all(.items[]; any(.status.conditions[]; .type==\"Available\" and .status==\"True\"))'"
check_eq "cp1 Ready" True kcq get node cp1 -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'
check "CoreDNS pods Running" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod -l k8s-app=kube-dns -o json | jq -e '(.items | length >= 2) and all(.items[]; .status.phase==\"Running\")'"
check "CoreDNS pod IPs are in 172.16.0.0/16" bash -c \
  "ips=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[*].status.podIP}'); [[ -n \$ips ]] && for ip in \$ips; do [[ \$ip == 172.16.* ]] || exit 1; done"

section "CNI on cp1"
real_conf=$(on cp1 bash -c 'ls /etc/cni/net.d/*.conflist /etc/cni/net.d/*.conf 2>/dev/null | sort | head -1')
check_eq "answers/04-cni.txt: config=${real_conf:-<a CNI config on cp1>}" "${real_conf:-<no CNI config on cp1>}" bash -c "sed -n 's/^config=//p' ~/answers/04-cni.txt"
check_eq "answers/04-cni.txt: bin_dir=/opt/cni/bin" /opt/cni/bin bash -c "sed -n 's/^bin_dir=//p' ~/answers/04-cni.txt | sed 's:/*$::'"

finish
