#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
kc delete ns e1-t4 --ignore-not-found --wait=true >/dev/null; kc create ns e1-t4 >/dev/null
victim=$(( RANDOM % 4 ))
for i in 0 1 2 3; do
  if [[ $i == "$victim" ]]; then cmd='echo "handling request"; sleep 5; echo "panic: runtime error: index out of range [7] with length 7"; exit 2'
  else cmd='while true; do echo "handling request"; sleep 5; done'; fi
  kc -n e1-t4 run api-$i --labels=tier=api --image=busybox:1.37 -- sh -c "$cmd" >/dev/null
done
kc -n e1-t4 run worker-0 --labels=tier=worker --image=busybox:1.37 -- sh -c 'echo "panic: in a worker, not an api pod"; sleep infinity' >/dev/null
echo "api-$victim" >"$LAB_STATE/exam1-t4-victim"
