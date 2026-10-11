#!/bin/bash
# Install (or update) the lab framework on the jump host.
#
#   PVE=root@192.168.8.200 infra/install-lab.sh [--solutions <dir>] [--no-token]
#
# - copies lab/ to /opt/cka-lab and links /usr/local/bin/lab
# - installs a grader-only kubectl in /opt/cka-lab/bin (students install their own)
# - optionally copies the private solutions repo to /opt/cka-lab-solutions
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
SOLUTIONS="" ROTATE=0 TOKEN=1
while (( $# )); do
  case $1 in
    --solutions) SOLUTIONS=$2; shift 2 ;;
    --rotate-token) ROTATE=1; shift ;;
    --no-token) TOKEN=0; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

source infra/lab.env
jump_vmid=$(awk '$8=="jump"{print $2}' <<<"$LAB_VMS")
pve() { ssh "${SSH_OPTS[@]}" "$PVE" "$@"; }

# The jump host's LAN address, from the QEMU guest agent.
JUMP_IP=$(pve "qm guest cmd $jump_vmid network-get-interfaces" |
  jq -r '.[] | select(.name=="eth0") | ."ip-addresses"[] | select(."ip-address-type"=="ipv4") | ."ip-address"' | head -1)
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
    COMPREPLY=($(compgen -W "list show start check solution exam snapshots snapshot reset" -- "$cur"))
  elif (( COMP_CWORD == 2 )) && [[ $prev =~ ^(show|start|check|solution)$ ]]; then
    COMPREPLY=($(compgen -W "$(ls /opt/cka-lab/labs)" -- "$cur"))
  elif (( COMP_CWORD == 3 )) && [[ $prev == exam ]]; then
    COMPREPLY=($(compgen -W "start show check status" -- "$cur"))
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

echo "[install] done: ssh -i $JUMP_KEY $JUMP   then   lab list"
