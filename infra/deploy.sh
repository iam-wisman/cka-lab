#!/bin/bash
# Render the cloud-init files, upload them to Proxmox and build the lab.
#
#   PVE=root@192.168.8.200 infra/deploy.sh
#
# Secrets never enter the repo. They are read from $CKA_LAB_SECRETS
# (default ~/.local/share/cka-lab):
#   lab_internal_ed25519[.pub]  key student@jump uses to reach the nodes
#   student-password            password for the `student` user (console/sudo)
# and your own public key from $USER_PUBKEY_FILE (default ~/.ssh/cka-lab.pub).
# Extra ssh options (e.g. a ControlPath) can be passed in $SSH_OPTS.

set -euo pipefail
cd "$(dirname "$0")"

PVE=${PVE:-root@192.168.8.200}
SECRETS=${CKA_LAB_SECRETS:-$HOME/.local/share/cka-lab}
USER_PUBKEY_FILE=${USER_PUBKEY_FILE:-$HOME/.ssh/cka-lab.pub}
read -ra SSH_OPTS <<<"${SSH_OPTS:-}"

source ./lab.env

for f in "$SECRETS/lab_internal_ed25519" "$SECRETS/lab_internal_ed25519.pub" "$SECRETS/student-password" "$USER_PUBKEY_FILE"; do
  [[ -f $f ]] || { echo "missing $f (see the header of this script)" >&2; exit 1; }
done

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

pw_hash=$(openssl passwd -6 -stdin <"$SECRETS/student-password")
user_pub=$(<"$USER_PUBKEY_FILE")
lab_pub=$(<"$SECRETS/lab_internal_ed25519.pub")
lab_priv_indented=$(sed 's/^/      /' "$SECRETS/lab_internal_ed25519")

render() {
  local src=$1 dest=$2 hostname=$3
  # Multi-line and slash-heavy values go through awk, not sed.
  awk -v domain="$LAB_DOMAIN" -v net="$LAB_NET" -v api="$API_ENDPOINT" -v host="$hostname" \
      -v pwh="$pw_hash" -v upub="$user_pub" -v lpub="$lab_pub" -v lpriv="$lab_priv_indented" '
    $0 == "@@LAB_PRIVKEY_INDENTED@@" { print lpriv; next }
    {
      gsub(/@@LAB_DOMAIN@@/, domain); gsub(/@@LAB_NET@@/, net); gsub(/@@API_ENDPOINT@@/, api)
      gsub(/@@HOSTNAME@@/, host)
      i = index($0, "@@STUDENT_PASSWORD_HASH@@"); if (i) $0 = substr($0, 1, i-1) pwh substr($0, i+25)
      i = index($0, "@@USER_PUBKEY@@"); if (i) $0 = substr($0, 1, i-1) upub substr($0, i+15)
      i = index($0, "@@LAB_PUBKEY@@");  if (i) $0 = substr($0, 1, i-1) lpub substr($0, i+14)
      print
    }' "$src" >"$dest"
  ! grep -q '@@' "$dest" || { echo "unrendered placeholder in $dest" >&2; exit 1; }
}

while read -r name _ _ _ _ _ _ role; do
  [[ -z $name || $name == \#* ]] && continue
  render "cloud-init/$( [[ $role == jump ]] && echo jump || echo node ).yaml" "$out/cka-$name.yaml" "$name"
done <<<"$LAB_VMS"

if [[ ${1:-} == --render-only ]]; then
  # Inspect what would be uploaded: infra/deploy.sh --render-only <dir>
  mkdir -p "$2" && cp "$out"/cka-*.yaml "$2/" && echo "[deploy] rendered into $2"
  exit 0
fi

echo "[deploy] uploading to $PVE"
# Cloud-init user-data must sit on a storage that allows the "snippets" content type.
ssh "${SSH_OPTS[@]}" "$PVE" bash -s -- "$SNIPPETS_STORAGE" <<'EOF'
set -e
content=$(awk -v s="$1" '$0 ~ "^[a-z]+: "s"$" {f=1; next} /^[a-z]+: / {f=0} f && $1=="content" {print $2}' /etc/pve/storage.cfg)
[[ ,$content, == *,snippets,* ]] || pvesm set "$1" --content "$content,snippets"
mkdir -p /var/lib/vz/snippets /root/cka-lab
chmod 700 /var/lib/vz/snippets
EOF
scp "${SSH_OPTS[@]}" -q "$out"/cka-*.yaml "$PVE:/var/lib/vz/snippets/"
ssh "${SSH_OPTS[@]}" "$PVE" "chmod 600 /var/lib/vz/snippets/cka-*.yaml"
scp "${SSH_OPTS[@]}" -q lab.env proxmox/build.sh "$PVE:/root/cka-lab/"

echo "[deploy] building"
ssh "${SSH_OPTS[@]}" "$PVE" "bash /root/cka-lab/build.sh"
