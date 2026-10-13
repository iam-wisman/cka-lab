#!/bin/bash
# Install (or update) the lab framework on the jump host.
#
#   PVE=root@192.168.8.200 infra/install-lab.sh [--solutions <dir>] [--no-token] [--web-password]
#   JUMP_IP=192.168.8.160 infra/install-lab.sh --no-token     (no Proxmox login needed)
#
# - copies lab/ to /opt/cka-lab and links /usr/local/bin/lab
# - installs a grader-only kubectl in /opt/cka-lab/bin (students install their own)
# - optionally copies the private solutions repo to /opt/cka-lab-solutions
# - installs the web console (lab/web) as lab-web.service on https://<jump>/, with a
#   self-signed certificate. It logs in with the student password, read from
#   $WEB_PASSWORD or ~/.local/share/cka-lab/student-password; --web-password
#   re-sets it on an existing install.
# - creates a Proxmox API token that can only snapshot/rollback/power the lab VMs
#   (pool "cka-lab", role "CKALab"), stored on the jump host in /etc/cka-lab/pve.env
#
# Safe to re-run; the token is only rotated when --rotate-token is given.

set -euo pipefail
cd "$(dirname "$0")/.."

PVE=${PVE:-root@192.168.8.200}
read -ra SSH_OPTS <<<"${SSH_OPTS:-}"
JUMP_KEY=${JUMP_KEY:-$HOME/.ssh/cka-lab}
GRADER_KUBECTL_VERSION=v1.35.9
SOLUTIONS="" ROTATE=0 TOKEN=1 WEB_PW_RESET=0
while (( $# )); do
  case $1 in
    --solutions) SOLUTIONS=$2; shift 2 ;;
    --rotate-token) ROTATE=1; shift ;;
    --no-token) TOKEN=0; shift ;;
    --web-password) WEB_PW_RESET=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

source infra/lab.env
jump_vmid=$(awk '$8=="jump"{print $2}' <<<"$LAB_VMS")
pve() { ssh "${SSH_OPTS[@]}" "$PVE" "$@"; }

# The jump host's LAN address, from the QEMU guest agent (or JUMP_IP=... to skip Proxmox).
JUMP_IP=${JUMP_IP:-$(pve "qm guest cmd $jump_vmid network-get-interfaces" |
  jq -r '.[] | select(.name=="eth0") | ."ip-addresses"[] | select(."ip-address-type"=="ipv4") | ."ip-address"' | head -1)}
[[ -n $JUMP_IP ]] || { echo "could not find the jump host's LAN IP" >&2; exit 1; }
JUMP=student@$JUMP_IP
jssh() { ssh -i "$JUMP_KEY" -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "$JUMP" "$@"; }
echo "[install] jump host is $JUMP_IP"

echo "[install] framework -> /opt/cka-lab"
tar -C lab -czf - . | jssh 'sudo mkdir -p /opt/cka-lab /etc/cka-lab && sudo tar -C /opt/cka-lab --no-same-owner -xzf - && sudo chmod -R a+rX /opt/cka-lab && sudo ln -sf /opt/cka-lab/bin/lab /usr/local/bin/lab && sudo chmod 755 /opt/cka-lab/bin/lab'
jssh "sudo install -m 644 /dev/stdin /etc/cka-lab/lab.env" <infra/lab.env
jssh 'sudo install -m 644 /dev/stdin /etc/bash_completion.d/lab' <<'EOF'
_lab() {
  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[1]:-}
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=($(compgen -W "list show start up check solution cleanup exam snapshots snapshot reset" -- "$cur"))
  elif (( COMP_CWORD == 2 )) && [[ $prev =~ ^(show|start|up|check|solution|cleanup)$ ]]; then
    COMPREPLY=($(compgen -W "$(ls /opt/cka-lab/labs)" -- "$cur"))
  elif (( COMP_CWORD == 3 )) && [[ $prev == exam ]]; then
    COMPREPLY=($(compgen -W "start up prep show check status cleanup" -- "$cur"))
  fi
}
complete -F _lab lab
EOF

echo "[install] grader kubectl $GRADER_KUBECTL_VERSION"
jssh "test -x /opt/cka-lab/bin/kubectl && /opt/cka-lab/bin/kubectl version --client -o json | jq -e '.clientVersion.gitVersion==\"$GRADER_KUBECTL_VERSION\"' >/dev/null || {
  curl -sfLo /tmp/kubectl https://dl.k8s.io/release/$GRADER_KUBECTL_VERSION/bin/linux/amd64/kubectl &&
  sudo install -m 755 /tmp/kubectl /opt/cka-lab/bin/kubectl && rm /tmp/kubectl; }"

if [[ -n $SOLUTIONS ]]; then
  echo "[install] solutions -> /opt/cka-lab-solutions"
  tar -C "$SOLUTIONS" --exclude=.git -czf - . | jssh 'sudo mkdir -p /opt/cka-lab-solutions && sudo tar -C /opt/cka-lab-solutions --no-same-owner -xzf - && sudo chmod -R a+rX /opt/cka-lab-solutions'
fi

if (( TOKEN )) && { (( ROTATE )) || ! jssh 'test -s /etc/cka-lab/pve.env'; }; then
  echo "[install] Proxmox API token for lab snapshots"
  ids=$(grep -Ev '^\s*(#|$)' <<<"$LAB_VMS" | awk '{print $2}' | paste -sd,)
  pve_node=$(pve hostname)
  secret=$(pve bash -s -- "$ids" <<'EOF'
set -e
ids=$1
has() { "$@" --output-format json | python3 -c 'import sys,json; sys.exit(0 if any(sys.argv[2] in (r.get(sys.argv[1]),) for r in json.load(sys.stdin)) else 1)' "$KEY" "$VAL"; }
KEY=poolid VAL=cka-lab has pveum pool list || pveum pool add cka-lab --comment "CKA lab VMs"
for id in ${ids//,/ }; do
  pvesh get /pools/cka-lab --output-format json | python3 -c 'import sys,json; sys.exit(0 if int(sys.argv[1]) in [m.get("vmid") for m in json.load(sys.stdin)["members"]] else 1)' "$id" ||
    pveum pool modify cka-lab --vms "$id"
done
KEY=roleid VAL=CKALab has pveum role list ||
  pveum role add CKALab --privs "VM.Audit VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback"
KEY=userid VAL=cka-lab@pve has pveum user list ||
  pveum user add cka-lab@pve --comment "CKA lab jump host: snapshot/rollback lab VMs only"
pveum acl modify /pool/cka-lab --users cka-lab@pve --roles CKALab
pveum user token remove cka-lab@pve jump >/dev/null 2>&1 || true
pveum user token add cka-lab@pve jump --privsep 0 --comment "used by lab snapshot/reset" --output-format json |
  python3 -c 'import sys,json; print(json.load(sys.stdin)["value"])'
EOF
)
  printf 'PVE_URL=https://%s:8006\nPVE_NODE=%s\nPVE_TOKEN=cka-lab@pve!jump=%s\n' "${PVE#*@}" "$pve_node" "$secret" |
    jssh 'sudo install -m 600 -o student -g student /dev/stdin /etc/cka-lab/pve.env'
fi

echo "[install] web console"
jssh 'dpkg -s python3-aiohttp >/dev/null 2>&1 || { sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y -qq python3-aiohttp >/dev/null; }'
if (( WEB_PW_RESET )) || ! jssh 'sudo test -s /etc/cka-lab/web.env'; then
  pw=${WEB_PASSWORD:-$(cat "$HOME/.local/share/cka-lab/student-password" 2>/dev/null || true)}
  [[ -n $pw ]] || { echo "set WEB_PASSWORD (or create ~/.local/share/cka-lab/student-password)" >&2; exit 1; }
  # Only a salted PBKDF2 hash goes to the jump host.
  hash=$(WEB_PW=$pw python3 - <<'PY'
import hashlib, os, secrets
salt, n = secrets.token_bytes(16), 600000
digest = hashlib.pbkdf2_hmac("sha256", os.environ["WEB_PW"].encode(), salt, n)
print(f"pbkdf2_sha256${n}${salt.hex()}${digest.hex()}")
PY
)
  # Single quotes: systemd must not expand the $ separators in the hash.
  printf "WEB_PASSWORD_HASH='%s'\nWEB_PORT=443\nWEB_CERT=/etc/cka-lab/web.crt\nWEB_KEY=/etc/cka-lab/web.key\n" "$hash" |
    jssh 'sudo install -m 600 -o student -g student /dev/stdin /etc/cka-lab/web.env'
fi
# Self-signed certificate for the jump host's LAN address; regenerated when the address changes.
jssh "sudo openssl x509 -in /etc/cka-lab/web.crt -noout -ext subjectAltName 2>/dev/null | grep -q 'IP Address:$JUMP_IP\$\|IP Address:$JUMP_IP,' || {
  sudo openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 825 -subj '/CN=Kubernetes Playgrounds' \
    -addext 'subjectAltName=IP:$JUMP_IP,DNS:jump.cka.lab,DNS:jump' -addext 'extendedKeyUsage=serverAuth' \
    -keyout /etc/cka-lab/web.key -out /etc/cka-lab/web.crt 2>/dev/null &&
  sudo chown student:student /etc/cka-lab/web.key /etc/cka-lab/web.crt && sudo chmod 600 /etc/cka-lab/web.key; }"
jssh 'sudo install -m 644 /opt/cka-lab/web/lab-web.service /etc/systemd/system/lab-web.service &&
  sudo systemctl daemon-reload && sudo systemctl enable -q lab-web && sudo systemctl restart lab-web'
echo "[install] web console: https://$JUMP_IP/  (self-signed certificate; log in with the student password)"

echo "[install] done: ssh -i $JUMP_KEY $JUMP   then   lab list"
