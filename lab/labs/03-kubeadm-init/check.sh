#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster

# yget <namespace> <configmap> <data-key> <python expression over `d`>
# Reads one YAML document out of a ConfigMap key and evaluates an expression on it.
yget() {
  kcq -n "$1" get cm "$2" -o "jsonpath={.data.${3//./\\.}}" |
    python3 -c 'import sys, yaml
d = yaml.safe_load(sys.stdin) or {}
try: v = eval(sys.argv[1], {"d": d})
except Exception: v = ""
print(v if not isinstance(v, (list, dict)) else yaml.safe_dump(v, default_flow_style=True).strip())' "$4"
}

section "ClusterConfiguration (kubeadm-config ConfigMap)"
check_eq "clusterName cka-lab" cka-lab yget kube-system kubeadm-config ClusterConfiguration 'd["clusterName"]'
check_match "kubernetesVersion v1.34.12 (or v1.35.9 after lab 07)" '^v1\.(34\.12|35\.9)$' yget kube-system kubeadm-config ClusterConfiguration 'd["kubernetesVersion"]'
check_eq "controlPlaneEndpoint k8s-api.cka.lab:6443" k8s-api.cka.lab:6443 yget kube-system kubeadm-config ClusterConfiguration 'd["controlPlaneEndpoint"]'
check_eq "podSubnet 172.16.0.0/16" 172.16.0.0/16 yget kube-system kubeadm-config ClusterConfiguration 'd["networking"]["podSubnet"]'
check_eq "serviceSubnet 10.112.0.0/16" 10.112.0.0/16 yget kube-system kubeadm-config ClusterConfiguration 'd["networking"]["serviceSubnet"]'
check_eq "dnsDomain cka.local" cka.local yget kube-system kubeadm-config ClusterConfiguration 'd["networking"]["dnsDomain"]'

section "API server certificate on cp1"
sans=$(on cp1 openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName 2>/dev/null)
check "SAN DNS:k8s-api.cka.lab" grep -q 'DNS:k8s-api.cka.lab' <<<"$sans"
check "SAN IP:10.10.10.10" grep -q 'IP Address:10.10.10.10\b' <<<"$sans"
check "SAN IP:10.112.0.1 (first service IP)" grep -q 'IP Address:10.112.0.1\b' <<<"$sans"
check "SAN DNS:kubernetes.default.svc.cka.local" grep -q 'DNS:kubernetes.default.svc.cka.local' <<<"$sans"

section "cp1 node registration"
check_eq "node cp1 exists with InternalIP 10.10.10.11" 10.10.10.11 kcq get node cp1 -o 'jsonpath={.status.addresses[?(@.type=="InternalIP")].address}'
check "kube-apiserver advertises 10.10.10.11" on cp1 grep -q -- '--advertise-address=10.10.10.11' /etc/kubernetes/manifests/kube-apiserver.yaml
check "/root/kubeadm-config.yaml has all four kinds" on cp1 bash -c \
  'f=/root/kubeadm-config.yaml; for k in InitConfiguration ClusterConfiguration KubeletConfiguration KubeProxyConfiguration; do grep -Eq "^kind:\s*$k\s*$" $f || exit 1; done'
check "criSocket set to containerd in the config file" on cp1 grep -Eq 'criSocket:\s*"?unix:///(var/)?run/containerd/containerd.sock' /root/kubeadm-config.yaml
check "certificates uploaded (kubeadm-certs Secret, or a control plane joined with them)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get secret kubeadm-certs >/dev/null 2>&1 ||
   $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get node cp2 -o name -l node-role.kubernetes.io/control-plane 2>/dev/null | grep -q ."

section "kubelet and kube-proxy component configs"
check_eq "kubelet cgroupDriver systemd" systemd yget kube-system kubelet-config kubelet 'd["cgroupDriver"]'
check_eq "kubelet serverTLSBootstrap true" True yget kube-system kubelet-config kubelet 'd["serverTLSBootstrap"]'
check_eq "kube-proxy mode nftables" nftables yget kube-system kube-proxy config.conf 'd["mode"]'
check "kube-proxy pods run with the nftables proxier" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system logs -l k8s-app=kube-proxy --tail=-1 2>/dev/null | grep -q 'Using nftables Proxier'"

section "kubelet serving certificate on cp1"
check "kubelet serves a certificate from the cluster CA" on cp1 bash -c \
  'openssl verify -CAfile /etc/kubernetes/pki/ca.crt /var/lib/kubelet/pki/kubelet-server-current.pem >/dev/null'
check "kubectl logs works for a pod on cp1" kc -n kube-system logs kube-apiserver-cp1 --tail=1
check "only kubelet-serving CSRs were approved by hand" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get csr -o json | jq -e '[.items[] | select(any(.status.conditions[]?; .type==\"Approved\" and .reason!=\"AutoApproved\")) | select(.spec.signerName != \"kubernetes.io/kubelet-serving\")] | length == 0'"

section "kubectl on jump (student)"
check_eq "~/.kube/config points at https://k8s-api.cka.lab:6443" https://k8s-api.cka.lab:6443 \
  kubectl config view --minify -o 'jsonpath={.clusters[0].cluster.server}'
check "kubectl get nodes works as student" kubectl get nodes
check "student's credentials are cluster-admin" bash -c 'kubectl auth can-i "*" "*" --all-namespaces | grep -qx yes'

finish
