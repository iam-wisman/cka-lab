#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace ts-net --ignore-not-found --wait=true >/dev/null
mk() { # mk <name> <text> <portname>
  kc apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1, namespace: ts-net}
spec:
  replicas: 1
  selector: {matchLabels: {app: $1}}
  template:
    metadata: {labels: {app: $1}}
    spec:
      containers:
        - {name: $1, image: hashicorp/http-echo:1.0, args: ["-listen=:8080", "-text=$2"], ports: [{containerPort: 8080, name: $3}]}
YAML
}
kc create namespace ts-net >/dev/null
mk checkout "checkout ok" http
mk payments "payments ok" http
mk inventory "inventory ok" http
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: checkout, namespace: ts-net}
spec: {selector: {app: checkout-v2}, ports: [{port: 80, targetPort: http}]}
---
apiVersion: v1
kind: Service
metadata: {name: payments, namespace: ts-net}
spec: {selector: {app: payments}, ports: [{port: 80, targetPort: https}]}
---
apiVersion: v1
kind: Service
metadata: {name: inventory, namespace: ts-net}
spec: {selector: {app: inventory}, ports: [{port: 80, targetPort: http}]}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: lockdown, namespace: ts-net}
spec:
  podSelector: {matchLabels: {app: inventory}}
  policyTypes: [Ingress]
---
apiVersion: v1
kind: Pod
metadata: {name: shopper, namespace: ts-net, labels: {app: shopper}}
spec:
  dnsPolicy: Default
  containers: [{name: c, image: busybox:1.37, command: [sleep, infinity]}]
YAML
# CoreDNS "reset to defaults": serves cluster.local instead of this cluster's cka.local
cf=$(kc -n kube-system get cm coredns -o jsonpath='{.data.Corefile}')
kc -n kube-system get cm coredns -o yaml >"$LAB_STATE/lab30-coredns-backup.yaml"
cf=${cf//kubernetes cka.local /kubernetes cluster.local }
kc -n kube-system create cm coredns --from-literal=Corefile="$cf" --dry-run=client -o yaml | kc apply -f - >/dev/null
kc -n kube-system rollout restart deploy/coredns >/dev/null
echo "Pod ts-net/shopper can't reach checkout, payments or inventory."
