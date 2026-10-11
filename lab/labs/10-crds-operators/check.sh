#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster
jqk() { kcq "${@:2}" -o json | jq -e "$1" >/dev/null; }
ready() { kcq "$@" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}'; }

section "A: cert-manager"
cm=$(helm_release cert-manager cert-manager)
check_eq "release cert-manager: chart cert-manager v1.21.2" "cert-manager v1.21.2" \
  jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${cm:-{\}}"
check "CRDs installed by the chart (crds.enabled)" jq -e '.config.crds.enabled == true' <<<"${cm:-{\}}"
check "CRDs kept on uninstall (crds.keep, the default, not disabled)" jq -e '(.config.crds.keep // true) == true' <<<"${cm:-{\}}"
check "cert-manager CRDs carry helm.sh/resource-policy: keep" jqk \
  '.metadata.annotations["helm.sh/resource-policy"] == "keep"' get crd certificates.cert-manager.io
check_eq "ClusterIssuer selfsigned-bootstrap is self-signed and Ready" "true True" bash -c \
  "echo \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterissuer selfsigned-bootstrap -o json | jq -r '.spec.selfSigned != null') \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterissuer selfsigned-bootstrap -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}')"
C=(-n cert-manager get certificate cka-root-ca)
check_eq "cka-root-ca Ready" True ready "${C[@]}"
check "cka-root-ca: isCA, CN 'CKA Lab Root CA', ECDSA 256, 10y, from selfsigned-bootstrap, Secret cka-root-ca" jqk '
  .spec.isCA == true and .spec.commonName == "CKA Lab Root CA" and .spec.secretName == "cka-root-ca"
  and .spec.privateKey.algorithm == "ECDSA" and ((.spec.privateKey.size // 256) == 256)
  and (.spec.duration == "87600h" or .spec.duration == "87600h0m0s")
  and .spec.issuerRef.name == "selfsigned-bootstrap" and .spec.issuerRef.kind == "ClusterIssuer"' "${C[@]}"
check_eq "ClusterIssuer cka-ca uses Secret cka-root-ca and is Ready" "cka-root-ca True" bash -c \
  "echo \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get clusterissuer cka-ca -o jsonpath='{.spec.ca.secretName} {.status.conditions[?(@.type==\"Ready\")].status}')"
A=(-n apps get certificate app-tls)
check_eq "apps/app-tls Ready" True ready "${A[@]}"
check "app-tls: names app.cka.lab + www.app.cka.lab, 30d, renew 10d before, from cka-ca" jqk '
  (.spec.dnsNames | sort) == ["app.cka.lab", "www.app.cka.lab"] and .spec.secretName == "app-tls"
  and (.spec.duration == "720h" or .spec.duration == "720h0m0s")
  and (.spec.renewBefore == "240h" or .spec.renewBefore == "240h0m0s")
  and .spec.issuerRef.name == "cka-ca" and .spec.issuerRef.kind == "ClusterIssuer"' "${A[@]}"
check "Secret apps/app-tls chains to CKA Lab Root CA" bash -c "
  t=\$(mktemp -d); k='$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG'
  \$k -n apps get secret app-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > \$t/leaf.pem
  \$k -n cert-manager get secret cka-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > \$t/ca.pem
  openssl x509 -in \$t/ca.pem -noout -subject | grep -q 'CKA Lab Root CA' && openssl verify -CAfile \$t/ca.pem \$t/leaf.pem >/dev/null"
want_crds=$(kcq get crd -o json | jq -r '.items[] | select(.metadata.labels["app.kubernetes.io/instance"]=="cert-manager") | .metadata.name' | sort)
check_eq "answers/10-cert-manager-crds.txt lists them sorted" "$want_crds" cat "$HOME/answers/10-cert-manager-crds.txt"

section "B: Backup CRD"
B=(get crd backups.ops.cka.lab)
check "CRD backups.ops.cka.lab: group, kind Backup, plural, singular, short name bk, Namespaced" jqk '
  .spec.group == "ops.cka.lab" and .spec.names.kind == "Backup" and .spec.names.plural == "backups"
  and .spec.names.singular == "backup" and (.spec.names.shortNames | index("bk")) and .spec.scope == "Namespaced"' "${B[@]}"
check "v1 served and storage" jqk 'any(.spec.versions[]; .name=="v1" and .served and .storage)' "${B[@]}"
check "status subresource enabled" jqk '.spec.versions[] | select(.name=="v1") | .subresources.status != null' "${B[@]}"
check "printer columns SCHEDULE, TARGET, RETENTION, PHASE (+ AGE)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG get bk -A 2>/dev/null | head -1 | grep -Eq 'SCHEDULE +TARGET +RETENTION +PHASE +AGE'"
check "ops/nightly exists" kc -n ops get backup nightly
check_eq "retentionDays defaulted to 7" 7 kcq -n ops get backup nightly -o 'jsonpath={.spec.retentionDays}'

reject() {   # reject <yaml spec body>: the API server must refuse it (server-side dry run)
  ! kc apply --dry-run=server -f - >/dev/null 2>&1 <<EOF
apiVersion: ops.cka.lab/v1
kind: Backup
metadata: {name: grader-probe, namespace: ops}
$1
EOF
}
accept() { ! reject "$1"; }
check "accepts a valid Backup" accept 'spec: {schedule: "*/15 * * * *", target: x, retentionDays: 30}'
check "rejects missing target" reject 'spec: {schedule: "0 2 * * *"}'
check "rejects missing schedule" reject 'spec: {target: x}'
check "rejects empty target" reject 'spec: {schedule: "0 2 * * *", target: ""}'
check "rejects a 3-field schedule" reject 'spec: {schedule: "0 2 *", target: x}'
check "rejects retentionDays 0" reject 'spec: {schedule: "0 2 * * *", target: x, retentionDays: 0}'
check "rejects retentionDays 31" reject 'spec: {schedule: "0 2 * * *", target: x, retentionDays: 31}'
check "rejects retentionDays \"7\" (string)" reject 'spec: {schedule: "0 2 * * *", target: x, retentionDays: "7"}'
check "status.phase enum enforced" bash -c "! $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n ops patch backup nightly --subresource=status --type=merge -p '{\"status\":{\"phase\":\"Exploded\"}}' --dry-run=server >/dev/null 2>&1"
check "status.phase settable through the status subresource" kc -n ops patch backup nightly --subresource=status --type=merge -p '{"status":{"phase":"Succeeded"}}' --dry-run=server

finish
