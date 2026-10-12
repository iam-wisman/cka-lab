#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster
ans() { sed -n "s/^$1=//p" "$HOME/answers/11-interfaces.txt" 2>/dev/null | head -1; }
# check_ans <key> <real value>: an empty real value means the grader couldn't read it, which never passes.
check_ans() { check_eq "$1" "${2:-<grader could not determine it>}" ans "$1"; }

section "1: the stranger on worker1"
check "no container named rogue in containerd (k8s.io namespace)" on worker1 bash -c '! ctr -n k8s.io containers ls -q | grep -qx rogue'
check "no task named rogue running" on worker1 bash -c '! ctr -n k8s.io tasks ls | awk "NR>1{print \$1}" | grep -qx rogue'
check_eq "containerd on worker1 not restarted since lab start" "$(cat "$LAB_STATE/lab11-containerd-start" 2>/dev/null || echo '<run lab start 11>')" \
  on worker1 systemctl show containerd -p ActiveEnterTimestampMonotonic --value

section "2: registry mirror on worker2"
H=/etc/containerd/certs.d/docker.io/hosts.toml
check "worker2 $H exists" on worker2 test -s "$H"
check "server = https://registry-1.docker.io (fallback)" on worker2 grep -Eq '^\s*server\s*=\s*"https://registry-1\.docker\.io"' "$H"
check "host mirror.gcr.io with pull and resolve capabilities" on worker2 bash -c \
  "grep -A3 -E '^\s*\[host\.\"https://mirror\.gcr\.io\"\]' $H | grep -Eq 'capabilities\s*=\s*\[.*\"pull\".*\"resolve\"|capabilities\s*=\s*\[.*\"resolve\".*\"pull\"'"
check "containerd's config_path includes /etc/containerd/certs.d" on worker2 bash -c \
  "containerd config dump 2>/dev/null | grep -E '^\s*config_path\s*=' | grep -q '/etc/containerd/certs.d'"
check "no deprecated registry.mirrors section in config.toml" on worker2 bash -c "! grep -q 'registry.mirrors' /etc/containerd/config.toml"
check "crictl pull docker.io/library/alpine:3.20 works on worker2" on worker2 crictl pull docker.io/library/alpine:3.20
check "worker1 has no docker.io mirror config (worker2 only)" on worker1 bash -c "! test -e $H"

section "3: RuntimeClass"
check_eq "RuntimeClass runc-std handler runc" runc kcq get runtimeclass runc-std -o 'jsonpath={.handler}'
check_eq "pod default/rc-test uses runc-std" runc-std kcq get pod rc-test -o 'jsonpath={.spec.runtimeClassName}'
check_eq "rc-test Running" Running kcq get pod rc-test -o 'jsonpath={.status.phase}'

section "4: answers"
real_ctr=$(on cp2 crictl ps --name '^kube-apiserver$' --state running -q 2>/dev/null | head -1)
real_pod=$(on cp2 crictl ps --name '^kube-apiserver$' --state running -o json 2>/dev/null | jq -r '.containers[0].podSandboxId // empty')
check_ans apiserver_container_cp2 "${real_ctr:0:13}"
check_ans apiserver_pod_sandbox_cp2 "${real_pod:0:13}"
real_ipam=$(on cp1 bash -c 'f=$(ls /etc/cni/net.d/*.conflist /etc/cni/net.d/*.conf 2>/dev/null | sort | head -1); jq -r "[.plugins[]? | .ipam.type // empty][0]" "$f"')
check_ans cni_ipam_plugin "$real_ipam"
# sed, not awk -F': ': the value itself contains colons (unix:///...).
real_sock=$(on worker1 sed -n 's/^containerRuntimeEndpoint: *//p' /var/lib/kubelet/config.yaml | tr -d '"')
[[ -z $real_sock ]] && real_sock=$(on worker1 bash -c "grep -o -- '--container-runtime-endpoint=[^ \"]*' /var/lib/kubelet/kubeadm-flags.env | cut -d= -f2")
check_ans cri_socket "$real_sock"
real_csi=$(kcq get csidrivers -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort | paste -sd,)
check_ans csi_drivers "${real_csi:-none}"

finish
