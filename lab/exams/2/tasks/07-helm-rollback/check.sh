#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
r=$(helm_release e2-t7 catalog)
check_eq "release now at revision 4" 4 jq -r .version <<<"${r:-{\}}"
check_eq "revision 4 is a rollback to 2" "Rollback to 2" jq -r .info.description <<<"${r:-{\}}"
check_eq "3 replicas available" 3 kcq -n e2-t7 get deploy catalog-podinfo -o 'jsonpath={.status.availableReplicas}'
check_eq "t7-revision.txt" 4 cat "$HOME/exam2/t7-revision.txt"
finish
