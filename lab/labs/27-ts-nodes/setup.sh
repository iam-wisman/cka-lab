#!/bin/bash
# Lab 27 setup: break worker1 and worker2 in different ways.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$LAB_STATE"
for n in worker1 worker2; do kc get node $n -o jsonpath='{.metadata.uid}' >"$LAB_STATE/lab27-$n-uid"; done

# worker1: runtime stopped and disabled, and the kubelet pointed at a socket that doesn't exist
on_script worker1 <<'SH'
set -e
systemctl disable --now containerd >/dev/null 2>&1
sed -i 's#^containerRuntimeEndpoint:.*#containerRuntimeEndpoint: unix:///var/run/containerd/containerd-shim.sock#' /var/lib/kubelet/config.yaml
systemctl restart kubelet
SH

# worker2: swap back on (persistently) and the kubelet's kubeconfig aimed at the wrong port
on_script worker2 <<'SH'
set -e
if [ ! -f /swap2.img ]; then fallocate -l 1G /swap2.img && chmod 600 /swap2.img && mkswap /swap2.img >/dev/null; fi
grep -q '^/swap2.img' /etc/fstab || echo '/swap2.img none swap sw 0 0' >> /etc/fstab
swapon /swap2.img 2>/dev/null || true
sed -i 's#server: https://k8s-api.cka.lab:6443#server: https://k8s-api.cka.lab:6444#' /etc/kubernetes/kubelet.conf
systemctl restart kubelet
SH
echo "Something happened to the workers. Give it a minute, then look at kubectl get nodes."
