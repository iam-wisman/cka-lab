#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster
R=$HOME/rbac
CA=$LAB_STATE/ca.crt
kcq config view --raw --minify -o 'jsonpath={.clusters[0].cluster.certificate-authority-data}' | base64 -d >"$CA" 2>/dev/null

# can <yes|no> <namespace|-> <verb> <resource> [--subresource=x] -- <impersonation flags...>
can() {
  local want=$1 ns=$2 verb=$3 res=$4; shift 4
  local nsflag=(-n "$ns"); [[ $ns == - ]] && nsflag=(--all-namespaces)
  local got; got=$(kc auth can-i "$verb" "$res" "${nsflag[@]}" "$@" 2>/dev/null)
  [[ $got == "$want" ]]
}
as_jane=(--as jane --as-group developers)
as_auditor=(--as ravi --as-group auditors)
as_deployer=(--as system:serviceaccount:ci:deployer)

section "jane's certificate"
check "~/rbac/jane.key exists" test -s "$R/jane.key"
check "~/rbac/jane.crt is signed by the cluster CA" openssl verify -CAfile "$CA" "$R/jane.crt"
check "certificate matches jane.key" bash -c \
  "[[ \$(openssl x509 -in $R/jane.crt -noout -pubkey | openssl sha256) == \$(openssl pkey -in $R/jane.key -pubout | openssl sha256) ]]"
check_match "subject CN=jane, O=developers" 'O ?= ?developers.*CN ?= ?jane|CN ?= ?jane.*O ?= ?developers' \
  openssl x509 -in "$R/jane.crt" -noout -subject
check "valid for 7 days (+/- 10 min)" bash -c "
  nb=\$(date -d \"\$(openssl x509 -in $R/jane.crt -noout -startdate | cut -d= -f2)\" +%s)
  na=\$(date -d \"\$(openssl x509 -in $R/jane.crt -noout -enddate | cut -d= -f2)\" +%s)
  d=\$((na - nb)); (( d > 604800 - 600 && d < 604800 + 600 ))"

section "jane.kubeconfig"
K=("$GRADER_KUBECTL" --kubeconfig "$R/jane.kubeconfig" --request-timeout=20s)
check_eq "current context jane@cka-lab" jane@cka-lab "${K[@]}" config current-context
check_eq "cluster cka-lab -> https://k8s-api.cka.lab:6443" "cka-lab https://k8s-api.cka.lab:6443" \
  "${K[@]}" config view --minify -o 'jsonpath={.clusters[0].name} {.clusters[0].cluster.server}'
check_eq "default namespace dev" dev "${K[@]}" config view --minify -o 'jsonpath={.contexts[0].context.namespace}'
check "CA, certificate and key embedded (no file paths)" bash -c \
  "c=\$($GRADER_KUBECTL --kubeconfig $R/jane.kubeconfig config view --raw --minify -o json) &&
   jq -e '.clusters[0].cluster[\"certificate-authority-data\"] and .users[0].user[\"client-certificate-data\"] and .users[0].user[\"client-key-data\"]' <<<\"\$c\""
check_eq "API server sees username jane" jane bash -c "$GRADER_KUBECTL --kubeconfig $R/jane.kubeconfig auth whoami -o jsonpath='{.status.userInfo.username}'"
check "API server sees group developers" bash -c "$GRADER_KUBECTL --kubeconfig $R/jane.kubeconfig auth whoami -o json | jq -e '.status.userInfo.groups | index(\"developers\")'"
check "jane can list deployments in dev with her kubeconfig" "${K[@]}" get deployments
check "jane is refused secrets with her kubeconfig" bash -c "! $GRADER_KUBECTL --kubeconfig $R/jane.kubeconfig get secrets 2>/dev/null"

section "developers in dev"
check "RoleBinding dev/developer binds Role developer to Group developers" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n dev get rolebinding developer -o json | jq -e '.roleRef.kind==\"Role\" and .roleRef.name==\"developer\" and any(.subjects[]; .kind==\"Group\" and .name==\"developers\") and all(.subjects[]; .kind==\"Group\")'"
for v in get list watch create update patch delete; do
  check "can $v deployments" can yes dev "$v" deployments.apps "${as_jane[@]}"
done
manage() { can yes dev create "$1" "${as_jane[@]}" && can yes dev update "$1" "${as_jane[@]}" && can yes dev delete "$1" "${as_jane[@]}"; }
for r in services configmaps; do
  check "can create, update and delete $r" manage "$r"
done
check "can delete pods" can yes dev delete pods "${as_jane[@]}"
check "can read pod logs (pods/log)" can yes dev get pods --subresource=log "${as_jane[@]}"
check "can list replicasets" can yes dev list replicasets.apps "${as_jane[@]}"
check "cannot create pods directly" can no dev create pods "${as_jane[@]}"
check "cannot delete replicasets" can no dev delete replicasets.apps "${as_jane[@]}"
check "cannot exec into pods (pods/exec)" can no dev create pods --subresource=exec "${as_jane[@]}"
check "cannot get secrets in dev" can no dev get secrets "${as_jane[@]}"
check "cannot list secrets in dev" can no dev list secrets "${as_jane[@]}"
check "no access in staging" can no staging list deployments.apps "${as_jane[@]}"

section "auditors (aggregation)"
check "ClusterRole cka-audit aggregates rbac.cka.lab/aggregate-to-audit=true" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterrole cka-audit -o json | jq -e 'any(.aggregationRule.clusterRoleSelectors[]; .matchLabels[\"rbac.cka.lab/aggregate-to-audit\"]==\"true\")'"
for cr in audit-nodes audit-storage; do
  check_eq "ClusterRole $cr labelled for aggregation" true kcq get clusterrole "$cr" -o 'jsonpath={.metadata.labels.rbac\.cka\.lab/aggregate-to-audit}'
done
check "ClusterRoleBinding auditors -> cka-audit for Group auditors" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterrolebinding auditors -o json | jq -e '.roleRef.name==\"cka-audit\" and any(.subjects[]; .kind==\"Group\" and .name==\"auditors\")'"
for r in nodes namespaces persistentvolumes storageclasses.storage.k8s.io; do
  check "auditors can list $r" can yes - list "$r" "${as_auditor[@]}"
done
check "auditors cannot delete nodes" can no - delete nodes "${as_auditor[@]}"
check "auditors cannot list pods" can no - list pods "${as_auditor[@]}"
check "auditors cannot get secrets" can no - get secrets "${as_auditor[@]}"

section "ci/deployer"
check_eq "automountServiceAccountToken false" false kcq -n ci get sa deployer -o 'jsonpath={.automountServiceAccountToken}'
for v in get list create update patch; do
  check "can $v deployments in staging" can yes staging "$v" deployments.apps "${as_deployer[@]}"
done
check "can patch deployments/scale in staging" can yes staging patch deployments.apps --subresource=scale "${as_deployer[@]}"
check "cannot delete deployments in staging" can no staging delete deployments.apps "${as_deployer[@]}"
check "cannot get secrets in staging" can no staging get secrets "${as_deployer[@]}"
check "cannot create deployments in dev" can no dev create deployments.apps "${as_deployer[@]}"
check "cannot create deployments in ci" can no ci create deployments.apps "${as_deployer[@]}"
check "Role and RoleBinding named deployer in staging" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n staging get role deployer >/dev/null && $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n staging get rolebinding deployer -o json | jq -e 'any(.subjects[]; .kind==\"ServiceAccount\" and .name==\"deployer\" and .namespace==\"ci\")'"
payload=$(python3 -c 'import sys, base64
p = open(sys.argv[1]).read().strip().split(".")[1]
print(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)).decode())' "$R/deployer.token" 2>/dev/null)
check_eq "deployer.token is for system:serviceaccount:ci:deployer" system:serviceaccount:ci:deployer jq -r .sub <<<"$payload"
check_eq "token lifetime exactly 2h (exp - iat)" 7200 jq -r '.exp - .iat' <<<"$payload"
check "token is accepted by the API server" bash -c \
  "$GRADER_KUBECTL --kubeconfig /dev/null --server https://k8s-api.cka.lab:6443 --certificate-authority $CA --token \"\$(cat $R/deployer.token)\" -n staging get deployments >/dev/null"

finish
