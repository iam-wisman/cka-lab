#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
sc() { kcq get sc nfs-csi -o json | jq -e "$1" >/dev/null; }

section "A: nfs server"
check "/dev/sdb has a GPT label with one partition" on nfs bash -c '[[ $(lsblk -no PTTYPE /dev/sdb | head -1) == gpt && $(lsblk -nro TYPE /dev/sdb | grep -c part) == 1 ]]'
check "partition is XFS labelled nfsdata" on nfs bash -c '[[ $(lsblk -no FSTYPE,LABEL /dev/sdb1 | xargs) == "xfs nfsdata" ]]'
check "mounted at /srv/nfs" on nfs bash -c '[[ $(findmnt -no SOURCE /srv/nfs) == /dev/sdb1 ]]'
check "fstab mounts /srv/nfs by UUID" on nfs bash -c \
  'u=$(blkid -s UUID -o value /dev/sdb1); grep -Ev "^\s*#" /etc/fstab | grep -Eq "^\s*UUID=\"?$u\"?\s+/srv/nfs\s+xfs"'
check "fstab entry valid (findmnt --verify)" on nfs bash -c 'findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1'
check "nfs-kernel-server active" on nfs systemctl is-active -q nfs-server
check "export /srv/nfs/k8s to 10.10.10.0/24 rw,sync,no_subtree_check,no_root_squash" on nfs bash -c \
  "exportfs -v | tr -d '\n\t ' | grep -Eq '/srv/nfs/k8s10\.10\.10\.0/24\(([^)]*,)?rw,' && exportfs -v | grep -A1 '/srv/nfs/k8s' | grep -q 'sync' && exportfs -v | grep -A1 '/srv/nfs/k8s' | grep -q 'no_root_squash' && exportfs -v | grep -A1 '/srv/nfs/k8s' | grep -q 'no_subtree_check'"
for n in "${K8S_NODES[@]}"; do
  check "$n has nfs-common" on "$n" bash -c "dpkg-query -W -f='\${Status}' nfs-common | grep -q 'install ok installed'"
done

section "B: CSI driver"
r=$(helm_release kube-system csi-driver-nfs)
check_eq "chart csi-driver-nfs v4.13.5" "csi-driver-nfs 4.13.5" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version | ltrimstr("v"))"' <<<"${r:-{\}}"
check "CSIDriver nfs.csi.k8s.io" kc get csidriver nfs.csi.k8s.io
check_eq "node plugin on all 5 nodes" 5 bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod -l app=csi-nfs-node -o json | jq '[.items[] | select(.status.phase==\"Running\") | .spec.nodeName] | unique | length'"

section "C: StorageClass nfs-csi"
check "provisioner, server, share" sc '.provisioner=="nfs.csi.k8s.io" and .parameters.server=="10.10.10.30" and .parameters.share=="/srv/nfs/k8s"'
check "subDir \${pvc.metadata.namespace}/\${pvc.metadata.name}" sc '.parameters.subDir=="${pvc.metadata.namespace}/${pvc.metadata.name}"'
check "Retain, Immediate, expansion allowed" sc '.reclaimPolicy=="Retain" and .volumeBindingMode=="Immediate" and .allowVolumeExpansion==true'
check "mountOptions nfsvers=4.1" sc '(.mountOptions // []) | index("nfsvers=4.1")'
check "nfs-csi is default" sc '.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true"'
check_eq "it's the only default StorageClass" nfs-csi bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get sc -o json | jq -r '[.items[] | select(.metadata.annotations[\"storageclass.kubernetes.io/is-default-class\"]==\"true\") | .metadata.name] | join(\" \")'"

section "D: shared volume"
check "PVC shared: RWX, 2Gi, no storageClassName in what you wrote, got nfs-csi" bash -c "
  j=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n storage get pvc shared -o json)
  jq -e '.spec.accessModes==[\"ReadWriteMany\"] and .spec.resources.requests.storage==\"2Gi\" and .spec.storageClassName==\"nfs-csi\" and .status.phase==\"Bound\"' <<<\"\$j\" >/dev/null &&
  ! jq -r '.metadata.annotations[\"kubectl.kubernetes.io/last-applied-configuration\"] // \"{}\"' <<<\"\$j\" | jq -e '.spec.storageClassName' >/dev/null"
check "writers: 2 ready pods on different nodes" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n storage get pod -l app=writers -o json | jq -e '[.items[] | select(.status.containerStatuses[0].ready) | .spec.nodeName] | length==2 and (unique|length)==2'"
check "log.txt on the nfs host has lines from both pods" bash -c "
  pods=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n storage get pod -l app=writers -o jsonpath='{.items[*].metadata.name}')
  [[ -n \$pods ]] && for p in \$pods; do ssh nfs sudo grep -q \$p /srv/nfs/k8s/storage/shared/log.txt || exit 1; done"
finish
