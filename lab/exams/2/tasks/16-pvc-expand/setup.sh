#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t16 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t16 >/dev/null
kc apply -f - >/dev/null <<'Y'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: logs, namespace: e2-t16}
spec: {accessModes: [ReadWriteMany], storageClassName: nfs-csi, resources: {requests: {storage: 1Gi}}}
---
apiVersion: v1
kind: Pod
metadata: {name: shipper, namespace: e2-t16}
spec:
  containers: [{name: s, image: busybox:1.37, command: [sleep, infinity], volumeMounts: [{name: l, mountPath: /logs}]}]
  volumes: [{name: l, persistentVolumeClaim: {claimName: logs}}]
Y
kc -n e2-t16 get pvc logs -o jsonpath='{.metadata.uid}' >"$LAB_STATE/exam2-t16-uid"
