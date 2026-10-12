#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
A=$HOME/answers

section "1: top CPU"
top=$(kcq top pods -n ts-obs --no-headers --sort-by=cpu | head -1 | awk '{print $1}')
check_eq "31-top-pod.txt is the busiest pod" "${top:-<no metrics>}" cat "$A/31-top-pod.txt"

section "2: previous instance"
check_eq "31-flaky.txt" "FATAL: lost connection to db-7.ts-obs (code 0x2f)" cat "$A/31-flaky.txt"

section "3: stderr only"
check "at least 5 lines" bash -c "(( \$(grep -c . $A/31-stderr.txt 2>/dev/null) >= 5 ))"
check "every line is an ERROR line, no INFO" bash -c "grep -q . $A/31-stderr.txt && ! grep -v '^ERROR code=E[0-9]* upstream timeout\$' $A/31-stderr.txt | grep -q ."
check "no timestamps or stream markers left" bash -c "grep -q . $A/31-stderr.txt && ! grep -Eq '^[0-9]{4}-|stderr|stdout' $A/31-stderr.txt"

section "4: multi-container"
check_eq "31-token.txt" "AUDIT-TOKEN=$(cat "$LAB_STATE/lab31-token" 2>/dev/null)" cat "$A/31-token.txt"

section "5: kubelet"
check_eq "31-badfile.txt" /etc/kubernetes/manifests/telemetry-agent.yaml cat "$A/31-badfile.txt"
check "the file is gone from worker1" on worker1 bash -c '! test -e /etc/kubernetes/manifests/telemetry-agent.yaml'
check "kubelet on worker1 healthy" on worker1 systemctl is-active -q kubelet
finish
