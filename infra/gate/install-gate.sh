#!/bin/bash
# Install (or update) the HelmYard gate: a tiny always-on container on Proxmox that
# starts the jump host and the cluster again after HelmYard shut itself down.
#
#   PVE=root@192.168.8.200 infra/gate/install-gate.sh [--ctid 207] [--rotate-token]
#
# - creates an unprivileged Alpine LXC (128 MB RAM, 1 GB disk on local-lvm, DHCP on
#   vmbr0, starts on boot) unless it exists, and installs python3 in it
# - gives it its own Proxmox API token (user cka-lab@pve, role CKALab on the cka-lab
#   pool: see infra/install-lab.sh), so it can only see and power the lab VMs
# - serves infra/gate/ on https://<gate>/ with a certificate from the console CA
#   (trust it once with tools/trust-console-ca.sh), and the student password
# - tells the console where the gate is (GATE_URL in /etc/cka-lab/web.env), so the
#   "HelmYard is off" page and the power controls link to it
#
# Safe to re-run: it updates the files and keeps the container and the token.

set -euo pipefail
cd "$(dirname "$0")/../.."

PVE=${PVE:-root@192.168.8.200}
read -ra SSH_OPTS <<<"${SSH_OPTS:-}"
CTID=207 ROTATE=0
while (( $# )); do
  case $1 in
    --ctid) CTID=$2; shift 2 ;;
    --rotate-token) ROTATE=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
JUMP_KEY=${JUMP_KEY:-$HOME/.ssh/cka-lab}
CA_DIR=${CA_DIR:-$HOME/.local/share/cka-lab}

source infra/lab.env
jump_vmid=$(awk '$8=="jump"{print $2}' <<<"$LAB_VMS")
node_vmids=$(awk '$8=="node"{print $2}' <<<"$LAB_VMS" | xargs)
pve() { ssh "${SSH_OPTS[@]}" "$PVE" "$@"; }
in_ct() { pve "pct exec $CTID -- $*"; }

pw=${WEB_PASSWORD:-$(cat "$CA_DIR/student-password" 2>/dev/null || true)}
[[ -n $pw ]] || { echo "set WEB_PASSWORD (or create $CA_DIR/student-password)" >&2; exit 1; }
[[ -f $CA_DIR/console-ca.key && -f $CA_DIR/console-ca.crt ]] || { echo "no console CA in $CA_DIR: run infra/install-lab.sh first" >&2; exit 1; }

# --- the container ---------------------------------------------------------------
if pve "pct status $CTID" >/dev/null 2>&1; then
  conf=$(pve "pct config $CTID")
  [[ $(sed -n 's/^hostname: //p' <<<"$conf") == helmyard-gate ]] ||
    { echo "CT $CTID exists and isn't helmyard-gate; pick another with --ctid" >&2; exit 1; }
  if [[ $(sed -n 's/^arch: //p' <<<"$conf") != amd64 ]]; then
    # An earlier run of this script picked the arm64 template, which can't start here: replace it.
    echo "[gate] container $CTID was built for $(sed -n 's/^arch: //p' <<<"$conf"); recreating it"
    pve "pct stop $CTID >/dev/null 2>&1; pct destroy $CTID --purge >/dev/null"
    pve "pveam list local | awk '/alpine-.*_arm64/ {print \$1}' | xargs -r -n1 pveam remove"
  else
    echo "[gate] container $CTID exists"
  fi
fi
if ! pve "pct status $CTID" >/dev/null 2>&1; then
  pve "qm status $CTID" >/dev/null 2>&1 && { echo "VM $CTID exists; pick another id with --ctid" >&2; exit 1; }
  echo "[gate] creating container $CTID (Alpine, 128 MB)"
  tmpl=$(pve "pveam update >/dev/null 2>&1; pveam available --section system" | awk '/alpine-3\.[0-9]+-default_.*_amd64\./ {print $2}' | sort -V | tail -1)
  [[ -n $tmpl ]] || { echo "no Alpine template offered by pveam" >&2; exit 1; }
  pve "pveam list local | grep -q '$tmpl' || pveam download local '$tmpl' >/dev/null"
  pve "pct create $CTID local:vztmpl/$tmpl --hostname helmyard-gate --description 'HelmYard gate: starts the lab again (infra/gate)' \
    --memory 128 --swap 0 --cores 1 --rootfs local-lvm:1 --net0 name=eth0,bridge=$UPLINK_BRIDGE,ip=dhcp \
    --unprivileged 1 --onboot 1 --startup order=1 --tags helmyard"
fi
pve "pct status $CTID | grep -q running || pct start $CTID"
for _ in $(seq 1 30); do
  GATE_IP=$(in_ct ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1) && [[ -n $GATE_IP ]] && break
  sleep 2
done
[[ -n ${GATE_IP:-} ]] || { echo "the gate container got no address" >&2; exit 1; }
echo "[gate] address $GATE_IP"
in_ct sh -c "'command -v python3 >/dev/null || apk add --no-cache -q python3 openssl'"

# --- token: may only see and power the lab VMs ---------------------------------------
for id in $jump_vmid $node_vmids; do
  pve "pvesh get /pools/cka-lab --output-format json" | jq -e --argjson id "$id" '.members[] | select(.vmid == $id)' >/dev/null ||
    { echo "VM $id isn't in the cka-lab pool (infra/install-lab.sh sets it up)" >&2; exit 1; }
done
pve_node=$(pve hostname)
if (( ROTATE )) || ! in_ct test -s /etc/helmyard-gate.token; then
  echo "[gate] Proxmox API token cka-lab@pve!gate"
  secret=$(pve "pveum user token remove cka-lab@pve gate >/dev/null 2>&1; pveum user token add cka-lab@pve gate --privsep 0 --comment 'HelmYard gate: start/stop the lab VMs' --output-format json" |
    python3 -c 'import sys,json; print(json.load(sys.stdin)["value"])')
  printf 'cka-lab@pve!gate=%s\n' "$secret" | pve "pct exec $CTID -- sh -c 'umask 077; cat >/etc/helmyard-gate.token'"
fi

# --- jump host address (the console) ------------------------------------------------
JUMP_IP=${JUMP_IP:-$(pve "qm guest cmd $jump_vmid network-get-interfaces" 2>/dev/null |
  jq -r '.[] | select(.name=="eth0") | ."ip-addresses"[] | select(."ip-address-type"=="ipv4") | ."ip-address"' | head -1)}
[[ -n $JUMP_IP ]] || { echo "the jump host is off or has no address; start it and re-run (or set JUMP_IP=...)" >&2; exit 1; }

# --- files, certificate, service ------------------------------------------------------
echo "[gate] files"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp infra/gate/gate.py infra/gate/index.html "$tmp/"
cp lab/web/static/brand/helmyard-mascot.png "$tmp/mascot.png"
cp lab/web/static/favicon.svg "$tmp/favicon.svg"
hash=$(WEB_PW=$pw python3 - <<'PY'
import hashlib, os, secrets
salt, n = secrets.token_bytes(16), 600000
print(f"pbkdf2_sha256${n}${salt.hex()}${hashlib.pbkdf2_hmac('sha256', os.environ['WEB_PW'].encode(), salt, n).hex()}")
PY
)
cat >"$tmp/helmyard-gate.env" <<EOF
PVE_URL=https://${PVE#*@}:8006
PVE_NODE=$pve_node
JUMP_VMID=$jump_vmid
NODE_VMIDS="$node_vmids"
CONSOLE_URL=https://$JUMP_IP/
PASSWORD_HASH='$hash'
PORT=443
CERT=/etc/helmyard-gate.crt
KEY=/etc/helmyard-gate.key
EOF
cat >"$tmp/helmyard-gate.initd" <<'EOF'
#!/sbin/openrc-run
description="HelmYard gate"
command=/usr/bin/python3
command_args=/opt/helmyard-gate/gate.py
command_background=yes
pidfile=/run/helmyard-gate.pid
start_pre() { set -a; . /etc/helmyard-gate.env; PVE_TOKEN=$(cat /etc/helmyard-gate.token); export PVE_TOKEN; set +a; }
depend() { need net; }
EOF
tar -C "$tmp" -czf - . | pve "pct exec $CTID -- sh -c 'mkdir -p /opt/helmyard-gate && tar -xzf - -C /opt/helmyard-gate &&
  mv /opt/helmyard-gate/helmyard-gate.env /etc/helmyard-gate.env && chmod 600 /etc/helmyard-gate.env &&
  mv /opt/helmyard-gate/helmyard-gate.initd /etc/init.d/helmyard-gate && chmod 755 /etc/init.d/helmyard-gate'"

# A certificate for the gate's address from the console CA (the key never leaves the container).
if ! in_ct sh -c "'openssl x509 -in /etc/helmyard-gate.crt -noout -ext subjectAltName 2>/dev/null | grep -q \"IP Address:$GATE_IP\"'"; then
  echo "[gate] certificate for $GATE_IP"
  ext=$tmp/ext csr=$tmp/csr crt=$tmp/crt
  printf 'subjectAltName=IP:%s,DNS:gate.cka.lab\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature\nbasicConstraints=critical,CA:FALSE\n' "$GATE_IP" >"$ext"
  in_ct sh -c "'umask 077; openssl ecparam -name prime256v1 -genkey -noout -out /etc/helmyard-gate.key && openssl req -new -key /etc/helmyard-gate.key -subj /CN=HelmYard-gate'" >"$csr"
  openssl x509 -req -in "$csr" -CA "$CA_DIR/console-ca.crt" -CAkey "$CA_DIR/console-ca.key" -CAcreateserial -CAserial "$CA_DIR/console-ca.srl" \
    -days 397 -sha256 -extfile "$ext" -out "$crt" 2>/dev/null
  cat "$crt" "$CA_DIR/console-ca.crt" | pve "pct exec $CTID -- sh -c 'cat >/etc/helmyard-gate.crt'"
fi
in_ct sh -c "'rc-update add helmyard-gate default >/dev/null 2>&1; rc-service helmyard-gate restart >/dev/null'"
sleep 2
curl -sk --max-time 5 "https://$GATE_IP/" | grep -q HelmYard || { echo "the gate doesn't answer on https://$GATE_IP/" >&2; exit 1; }

# --- tell the console where the gate is -------------------------------------------
echo "[gate] console on $JUMP_IP: GATE_URL=https://$GATE_IP/"
ssh -i "$JUMP_KEY" -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR "student@$JUMP_IP" \
  "sudo sed -i '/^GATE_URL=/d' /etc/cka-lab/web.env && echo 'GATE_URL=https://$GATE_IP/' | sudo tee -a /etc/cka-lab/web.env >/dev/null && sudo systemctl restart lab-web"

echo "[gate] done: https://$GATE_IP/  (sign in with the student password)"
echo "       Give the gate and the jump host fixed DHCP leases, so their addresses don't move."
