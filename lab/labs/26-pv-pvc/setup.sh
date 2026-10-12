#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc get sc nfs-csi >/dev/null 2>&1 || die "lab 25 (StorageClass nfs-csi) must be done first"
kc delete namespace pv-lab --ignore-not-found --wait=true >/dev/null
kc delete pv archive-pv local-vol1 --ignore-not-found >/dev/null
on nfs bash -c 'mkdir -p /srv/nfs/k8s/archive && echo "Q3 ledger close: 4,812,330.17" > /srv/nfs/k8s/archive/important.txt'
kc create namespace pv-lab >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata: {name: archive-pv}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  mountOptions: [nfsvers=4.1]
  nfs: {server: 10.10.10.30, path: /srv/nfs/k8s/archive}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: archive-old, namespace: pv-lab}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ""
  volumeName: archive-pv
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: growing, namespace: pv-lab}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-csi
  resources: {requests: {storage: 1Gi}}
YAML
for _ in $(seq 1 30); do [[ $(kc get pv archive-pv -o jsonpath='{.status.phase}') == Bound ]] && break; sleep 2; done
kc -n pv-lab delete pvc archive-old --wait=true >/dev/null
kc get pv archive-pv -o jsonpath='{.metadata.uid}' >"$LAB_STATE/lab26-archive-uid"
echo "PV archive-pv is now $(kc get pv archive-pv -o jsonpath='{.status.phase}')."
