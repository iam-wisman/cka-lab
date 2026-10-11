#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

K8S_VERSION=1.34.12

# The pause image kubeadm expects, asked from kubeadm itself where it exists.
pause_image=$(on cp1 kubeadm config images list --kubernetes-version "v$K8S_VERSION" 2>/dev/null | grep /pause:)
pause_image=${pause_image:-registry.k8s.io/pause:3.10.1}

for n in "${K8S_NODES[@]}"; do
  section "$n"
  if ! node_up "$n"; then
    check "$n is reachable over SSH" false
    continue
  fi

  check_eq "swap is off" "" on "$n" tail -n +2 /proc/swaps
  check "no swap entry is active in /etc/fstab" on "$n" bash -c '! grep -Ev "^\s*#" /etc/fstab | awk "\$3==\"swap\"" | grep -q .'

  for m in overlay br_netfilter; do
    check "module $m loaded" on "$n" bash -c "grep -q '^$m ' /proc/modules"
    check "module $m persisted in /etc/modules-load.d" on "$n" bash -c "grep -hqsx '\s*$m\s*' /etc/modules-load.d/*.conf"
  done

  for s in net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward; do
    check_eq "$s = 1 (live)" 1 on "$n" sysctl -n "$s"
    check "$s = 1 persisted in /etc/sysctl.d" on "$n" bash -c \
      "grep -hEqs '^\s*${s//./\\.}\s*=\s*1\s*$' /etc/sysctl.d/*.conf"
  done

  check_match "containerd 2.x from containerd.io" '^2\.' on "$n" bash -c "dpkg-query -W -f='\${Version}' containerd.io"
  check "containerd enabled and active" on "$n" bash -c 'systemctl is-enabled -q containerd && systemctl is-active -q containerd'
  check "CRI plugin enabled (not in disabled_plugins)" on "$n" bash -c 'cfg=$(containerd config dump 2>/dev/null) && ! grep -E "^disabled_plugins" <<<"$cfg" | grep -q cri'
  check "runc uses the systemd cgroup driver" on "$n" bash -c \
    "containerd config dump 2>/dev/null | grep -A30 \"runtimes.runc.options\]\" | grep -Eq '^\s*SystemdCgroup = true'"
  check_eq "sandbox image is $pause_image" "$pause_image" on "$n" bash -c \
    "containerd config dump 2>/dev/null | sed -n \"/pinned_images\]/,/^\s*\[/p\" | sed -n \"s/^\s*sandbox = '\(.*\)'/\1/p\""

  check "crictl.yaml sets runtime-endpoint to containerd" on "$n" bash -c \
    "grep -Eq '^runtime-endpoint:\s*unix:///(var/)?run/containerd/containerd.sock' /etc/crictl.yaml"
  check "crictl.yaml sets image-endpoint to containerd" on "$n" bash -c \
    "grep -Eq '^image-endpoint:\s*unix:///(var/)?run/containerd/containerd.sock' /etc/crictl.yaml"
  check "crictl ps works without warnings" on "$n" bash -c '! crictl ps 2>&1 >/dev/null | grep -qi . && crictl ps >/dev/null'

  check "pkgs.k8s.io v1.34 repository configured" on "$n" bash -c \
    "grep -rhqs 'pkgs.k8s.io/core:/stable:/v1.34/deb' /etc/apt/sources.list.d/"
  for p in kubeadm kubelet kubectl; do
    check_match "$p is $K8S_VERSION" "^${K8S_VERSION//./\\.}-" on "$n" bash -c "dpkg-query -W -f='\${Version}' $p"
    check "$p is held" on "$n" bash -c "apt-mark showhold | grep -qx $p"
  done
  check "kubelet service enabled" on "$n" systemctl is-enabled -q kubelet
done

section "jump (student)"
check_match "kubectl is $K8S_VERSION" "^${K8S_VERSION//./\\.}-" dpkg-query -W -f='${Version}' kubectl
check "kubectl is held" bash -c 'apt-mark showhold | grep -qx kubectl'
check "kubectl completion loaded in a login shell" bash -lic 'complete -p kubectl'
check "alias k exists in a login shell" bash -lic 'alias k'
check "completion works for k" bash -lic 'complete -p k | grep -q __start_kubectl'

finish
