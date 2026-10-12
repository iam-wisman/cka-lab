#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "CRD established" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get crd databaseclaims.data.cka.lab -o json | jq -e 'any(.status.conditions[]; .type==\"Established\" and .status==\"True\")'"
check_eq "orders-db: postgres 20Gi 2" "postgres 20Gi 2" kcq -n e2-t8 get dbc orders-db -o 'jsonpath={.spec.engine} {.spec.storageSize} {.spec.replicaCount}'
finish
