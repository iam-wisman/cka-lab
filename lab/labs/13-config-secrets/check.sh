#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
C=$HOME/config
x() { kc -n config exec app -c "${1}" -- "${@:2}" 2>/dev/null; }

section "ConfigMaps and Secrets"
check_eq "app-props has exactly one key app.properties" app.properties bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get cm app-props -o json | jq -r '.data | keys | join(\" \")'"
check_eq "app-props content matches the file" "$(cat "$C/app.properties" 2>/dev/null)" kcq -n config get cm app-props -o 'jsonpath={.data.app\.properties}'
check_eq "app-env keys LOG_LEVEL MAX_CONN REGION" "LOG_LEVEL MAX_CONN REGION" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get cm app-env -o json | jq -r '.data | keys | join(\" \")'"
check_eq "app-env immutable" true kcq -n config get cm app-env -o 'jsonpath={.immutable}'
check_eq "nginx-conf key nginx.conf" "$(cat "$C/nginx.conf" 2>/dev/null)" kcq -n config get cm nginx-conf -o 'jsonpath={.data.nginx\.conf}'
check_eq "Secret db username=app" app bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get secret db -o jsonpath='{.data.username}' | base64 -d"
check_eq "Secret db password from file (no trailing newline added)" "$(cat "$C/db-password.txt" 2>/dev/null)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get secret db -o jsonpath='{.data.password}' | base64 -d"
check_eq "Secret web-tls type kubernetes.io/tls" kubernetes.io/tls kcq -n config get secret web-tls -o 'jsonpath={.type}'
check_eq "web-tls holds tls.crt from the file" "$(openssl x509 -in "$C/tls.crt" -noout -fingerprint 2>/dev/null)" bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get secret web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -fingerprint"

section "pod app"
check_eq "Running, 2/2 ready" "Running true true" kcq -n config get pod app -o 'jsonpath={.status.phase} {.status.containerStatuses[0].ready} {.status.containerStatuses[1].ready}'
check_eq "label app=config-demo" config-demo kcq -n config get pod app -o 'jsonpath={.metadata.labels.app}'
check_eq "CFG_LOG_LEVEL=debug CFG_REGION=eu-west CFG_MAX_CONN=40" "debug eu-west 40" x main sh -c 'echo $CFG_LOG_LEVEL $CFG_REGION $CFG_MAX_CONN'
check_eq "DB_USER=app from the Secret" app x main sh -c 'echo $DB_USER'
check "DB_USER uses secretKeyRef (not a literal)" bash -c \
  "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n config get pod app -o json | jq -e '.spec.containers[] | select(.name==\"main\") | .env[] | select(.name==\"DB_USER\") | .valueFrom.secretKeyRef.name==\"db\" and .valueFrom.secretKeyRef.key==\"username\"'"
check_eq "/etc/app contains only application.properties" application.properties x main ls /etc/app
check_eq "/etc/app/application.properties content" "$(cat "$C/app.properties" 2>/dev/null)" x main cat /etc/app/application.properties
check_eq "/run/secrets/db/password mode 400" 400 x main stat -L -c %a /run/secrets/db/password
check "/run/secrets/db is mounted read-only" x main sh -c '! touch /run/secrets/db/x 2>/dev/null'
check_eq "/etc/meta lists labels mem_limit props tls.crt" "labels mem_limit props tls.crt" x main sh -c 'ls /etc/meta | sort | tr "\n" " " | sed "s/ $//"'
check_eq "/etc/meta/mem_limit is 96" 96 x main cat /etc/meta/mem_limit
check "/etc/meta/labels has app=\"config-demo\"" x main grep -qx 'app="config-demo"' /etc/meta/labels
check "/etc/meta has no tls.key" x main sh -c '! ls /etc/meta/tls.key 2>/dev/null'
check_eq "nginx serves the custom config on 8081" "custom nginx.conf" x nginx wget -qO- http://127.0.0.1:8081/
check "nginx still has /etc/nginx/mime.types (subPath, not a directory mount)" x nginx test -f /etc/nginx/mime.types
finish
