#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
who="system:serviceaccount:$NS:$SA"
can() { [[ $(kcq auth can-i "$@" --as "$who") == yes ]]; }
cannot() { ! can "$@"; }
check "Role $ROLE and RoleBinding $ROLE exist" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n $NS get role/$ROLE rolebinding/$ROLE >/dev/null 2>&1"
for v in get list watch create delete update patch; do
  if [[ ,$VERBS, == *,$v,* ]]; then check "can $v $RES" can "$v" "$RES" -n "$NS"
  else check "can't $v $RES" cannot "$v" "$RES" -n "$NS"; fi
done
other=configmaps; [[ $RES == configmaps ]] && other=secrets
check "can't touch $other" cannot get "$other" -n "$NS"
check "can't read $RES in other namespaces" cannot get "$RES" -n default
finish
