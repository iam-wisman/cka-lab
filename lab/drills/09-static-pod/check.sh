#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
mirror=$POD-$NODE
pj() { kcq -n "$NS" get pod "$mirror" -o json | jq -e "$1" >/dev/null; }
check "mirror pod $mirror exists in $NS" pj '.metadata.annotations["kubernetes.io/config.mirror"] != null'
check "runs $IMG on $NODE" pj ".spec.nodeName==\"$NODE\" and .spec.containers[0].image==\"$IMG\" and .status.phase==\"Running\""
# Root on the node: the manifests directory isn't readable by student, so the glob must
# expand there.
static_manifest() {
  on "$NODE" bash -c 'd=$(awk "/^staticPodPath:/{print \$2}" /var/lib/kubelet/config.yaml); grep -lE "^[[:space:]]+name: $1[[:space:]]*$" "$d"/*' _ "$POD"
}
check "the manifest is in $NODE's staticPodPath" static_manifest
finish
