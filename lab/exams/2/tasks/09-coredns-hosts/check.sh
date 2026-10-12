#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
resolves() { kc -n default run dnsprobe-$RANDOM --rm -i --restart=Never --image=busybox:1.37 -q -- nslookup "$1" 2>/dev/null | sed -n '/^Name:/,$p' | grep -q "$2"; }
check "vault.cka.lab -> 10.10.10.30" resolves vault.cka.lab 10.10.10.30
check "kubernetes.default.svc.cka.local still resolves" resolves kubernetes.default.svc.cka.local 10.112.0.1
check "jump.cka.lab still resolves" resolves jump.cka.lab 10.10.10.10
finish
