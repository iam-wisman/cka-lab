#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam1" "$LAB_STATE"
on cp1 rm -f /var/backups/etcd/exam1.db /var/backups/etcd/exam1.status
date +%s >"$LAB_STATE/exam1-t6-start"
