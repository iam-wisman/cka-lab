#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
drill_ns "$NS"
if [[ $TARGET == 1 ]]; then causes=("$CAUSE" "$OTHERA" "$OTHERB"); else causes=("$OTHERA" "$CAUSE" "$OTHERB"); fi
tags=(1.25-alpine 1.26-alpine 1.27-alpine)
kc -n "$NS" create deployment "$DEP" --image="nginx:${tags[0]}" --replicas=2 >/dev/null
for i in 0 1 2; do
  (( i )) && kc -n "$NS" set image "deploy/$DEP" "nginx=nginx:${tags[$i]}" >/dev/null
  kc -n "$NS" annotate "deploy/$DEP" kubernetes.io/change-cause="${causes[$i]}" --overwrite >/dev/null
  kc -n "$NS" rollout status "deploy/$DEP" --timeout=180s >/dev/null
done
