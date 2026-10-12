#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
ns() { kc -n dns exec probe -- timeout 6 nslookup "$1" 2>/dev/null; }
resolves_to() { ns "$1" | sed -n '/^Name:/,$p' | grep -q "Address:\? *$2\b"; }
ans() { sed -n "s/^$1=//p" "$HOME/answers/24-dns.txt" 2>/dev/null | head -1 | sed 's/\.$//'; }
dnsip=$(kcq -n kube-system get svc kube-dns -o 'jsonpath={.spec.clusterIP}')

section "Corefile"
check "db.corp.internal -> 10.10.10.30 (stub domain)" resolves_to db.corp.internal 10.10.10.30
check "corp.internal uses its own server block forwarding to 10.10.10.10" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -Pzo '(?s)corp\.internal(:53)?\s*\{[^}]*forward\s+\.\s+10\.10\.10\.10' >/dev/null"
check "registry.cka.lab -> 10.10.10.10" resolves_to registry.cka.lab 10.10.10.10
check "nfs.cka.lab still resolves (10.10.10.30)" resolves_to nfs.cka.lab 10.10.10.30
check "kubernetes.default still resolves" resolves_to kubernetes.default.svc.cka.local 10.112.0.1
check "external names still resolve (pkgs.k8s.io)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n dns exec probe -- timeout 6 nslookup pkgs.k8s.io 2>/dev/null | sed -n '/^Name:/,\$p' | grep -q Address"
check "reload plugin present (changes applied without restarts)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -Eq '^\s*reload\b'"
check_eq "CoreDNS: 2/2 available" "2 2" kcq -n kube-system get deploy coredns -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'

section "dns-tuned"
p() { kcq -n dns get pod dns-tuned -o json | jq -e "$1" >/dev/null; }
check "dnsPolicy None" p '.spec.dnsPolicy=="None"'
check "nameserver = cluster DNS IP" p ".spec.dnsConfig.nameservers==[\"$dnsip\"]"
check "searches dns.svc.cka.local svc.cka.local cka.local" p '.spec.dnsConfig.searches==["dns.svc.cka.local","svc.cka.local","cka.local"]'
check "ndots 2" p 'any(.spec.dnsConfig.options[]; .name=="ndots" and .value=="2")'
check_eq "resolv.conf inside the pod matches" "nameserver $dnsip|search dns.svc.cka.local svc.cka.local cka.local|options ndots:2" \
  bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n dns exec dns-tuned -- cat /etc/resolv.conf 2>/dev/null | grep -E '^(nameserver|search|options)' | paste -sd'|'"

section "answers"
check_eq "cluster_dns_ip" "${dnsip:-?}" ans cluster_dns_ip
check_eq "catalog_fqdn" catalog.dns.svc.cka.local ans catalog_fqdn
check_eq "api_fqdn" kubernetes.default.svc.cka.local ans api_fqdn
finish
