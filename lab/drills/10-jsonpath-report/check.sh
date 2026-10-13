#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
want=$(kcq -n kube-system get pods --field-selector "spec.nodeName=$NODE" -o json | jq -r '.items | sort_by(.metadata.name)[] | "\(.metadata.name) \(.spec.containers[0].image)"')
check "~/answers/drill-$FILE.txt exists" test -s "$HOME/answers/drill-$FILE.txt"
check_eq "it lists exactly $NODE's kube-system pods, sorted" "$want" cat "$HOME/answers/drill-$FILE.txt"
finish
