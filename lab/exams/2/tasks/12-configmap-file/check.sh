#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "ConfigMap app-conf" mode=strict kcq -n e2-t12 get cm app-conf -o 'jsonpath={.data.app\.conf}'
check_eq "file in the running container" mode=strict kc -n e2-t12 exec deploy/app -- cat /etc/app/app.conf
check_eq "Deployment available" 1 kcq -n e2-t12 get deploy app -o 'jsonpath={.status.availableReplicas}'
finish
