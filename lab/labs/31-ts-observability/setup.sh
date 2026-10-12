#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace ts-obs --ignore-not-found --wait=true >/dev/null
token=$(openssl rand -hex 6)
mkdir -p "$LAB_STATE" "$HOME/answers"; echo "$token" >"$LAB_STATE/lab31-token"
kc apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Namespace
metadata: {name: ts-obs}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: alpha, namespace: ts-obs}
spec:
  replicas: 1
  selector: {matchLabels: {app: alpha}}
  template:
    metadata: {labels: {app: alpha}}
    spec: {containers: [{name: c, image: busybox:1.37, command: [sh, -c, "while true; do sleep 1; done"]}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: beta, namespace: ts-obs}
spec:
  replicas: 1
  selector: {matchLabels: {app: beta}}
  template:
    metadata: {labels: {app: beta}}
    spec:
      containers:
        - {name: c, image: busybox:1.37, command: [sh, -c, "while true; do :; done"], resources: {limits: {cpu: 300m}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: gamma, namespace: ts-obs}
spec:
  replicas: 1
  selector: {matchLabels: {app: gamma}}
  template:
    metadata: {labels: {app: gamma}}
    spec:
      containers:
        - {name: c, image: busybox:1.37, command: [sh, -c, "while true; do i=0; while [ \$i -lt 20000 ]; do i=\$((i+1)); done; sleep 1; done"], resources: {limits: {cpu: 100m}}}
---
apiVersion: v1
kind: Pod
metadata: {name: flaky, namespace: ts-obs}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: [sh, -c, 'echo "starting worker"; sleep 8; echo "FATAL: lost connection to db-7.ts-obs (code 0x2f)"; exit 3']
---
apiVersion: v1
kind: Pod
metadata: {name: mixed, namespace: ts-obs}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: [sh, -c, 'n=0; while true; do n=\$((n+1)); echo "INFO request \$n served"; if [ \$((n % 3)) -eq 0 ]; then echo "ERROR code=E\$n upstream timeout" >&2; fi; sleep 1; done']
---
apiVersion: v1
kind: Pod
metadata: {name: multi, namespace: ts-obs}
spec:
  containers:
    - {name: app, image: busybox:1.37, command: [sh, -c, 'while true; do echo "app heartbeat"; sleep 5; done']}
    - {name: audit, image: busybox:1.37, command: [sh, -c, 'echo "AUDIT-TOKEN=$token"; while true; do echo "audit idle"; sleep 5; done']}
YAML
# worker1's kubelet gets an unparsable static pod manifest it will complain about
on worker1 bash -c 'printf "apiVersion: v1\nkind: Pod\nmetadata:\n  name: telemetry\n spec:\n  containers: [\n" > /etc/kubernetes/manifests/telemetry-agent.yaml'
echo "Give the pods a minute to run (and crash) before you start."
