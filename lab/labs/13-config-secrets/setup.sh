#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace config --ignore-not-found --wait=true >/dev/null
kc create namespace config >/dev/null
C=$HOME/config; rm -rf "$C"; mkdir -p "$C"
cat >"$C/app.properties" <<'P'
server.port=8080
cache.size=512
feature.newCheckout=true
P
cat >"$C/app.env" <<'P'
LOG_LEVEL=debug
REGION=eu-west
MAX_CONN=40
P
printf 'Tr0ub4dor&3-%s' "$(openssl rand -hex 4)" >"$C/db-password.txt"
cat >"$C/nginx.conf" <<'P'
events {}
http { server { listen 8081; location / { return 200 "custom nginx.conf\n"; } } }
P
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=config.cka.lab" \
  -keyout "$C/tls.key" -out "$C/tls.crt" 2>/dev/null
echo "Input files are in $C"
