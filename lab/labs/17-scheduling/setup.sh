#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace sched --ignore-not-found --wait=true >/dev/null
kc create namespace sched >/dev/null
kc taint node worker2 dedicated=analytics:NoSchedule --overwrite >/dev/null
kc label node worker1 disktype- >/dev/null 2>&1 || true
echo "worker2 is now dedicated to analytics (tainted)."
