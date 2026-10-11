#!/bin/bash
# Lab 05 setup: plant a forged kubelet-serving CSR among the real ones.
# It claims to be worker1 but asks for the API load balancer's name and IP too
# (a certificate that would let its holder impersonate the API endpoint), and
# it is submitted by kubernetes-admin, not by the node. It must be denied.
source "$LAB_HOME/lib/common.sh"
set -euo pipefail

grader_kubeconfig || die "the API server must be reachable (finish lab 03/04 first)"

state=$LAB_STATE/lab05-forged-csr
if [[ -f $state ]] && kc get csr "$(<"$state")" >/dev/null 2>&1; then
  exit 0   # already planted
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/key.pem" 2>/dev/null
openssl req -new -key "$tmp/key.pem" -out "$tmp/req.pem" \
  -subj "/O=system:nodes/CN=system:node:worker1" \
  -addext "subjectAltName=DNS:worker1,DNS:k8s-api.cka.lab,IP:10.10.10.21,IP:10.10.10.10" 2>/dev/null

name=csr-$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)
kc apply -f - >/dev/null <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $name
spec:
  signerName: kubernetes.io/kubelet-serving
  request: $(base64 -w0 "$tmp/req.pem")
  usages: [digital signature, server auth]
EOF
mkdir -p "$LAB_STATE"
echo "$name" >"$state"
