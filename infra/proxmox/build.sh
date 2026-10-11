#!/bin/bash
# Build the CKA lab VMs on a Proxmox host. Run as root on the host, after
# infra/deploy.sh has uploaded lab.env and the rendered cloud-init snippets.
#
#   build.sh            create any missing lab VMs, boot them, snapshot "base"
#   build.sh --destroy  remove every lab VM (IDs from lab.env) -- asks first
#
# Idempotent: existing VMs are left alone. Only touches the VM IDs in lab.env.

set -euo pipefail
cd "$(dirname "$0")"
source ./lab.env

log() { printf '\e[36m[build]\e[0m %s\n' "$*"; }

vms() { grep -Ev '^\s*(#|$)' <<<"$LAB_VMS"; }

wait_for_cloud_init() {
  local vmid=$1 name=$2 i
  for i in $(seq 1 120); do
    qm agent "$vmid" ping >/dev/null 2>&1 && break
    sleep 5
  done
  qm agent "$vmid" ping >/dev/null 2>&1 || { log "$name: guest agent never came up"; return 1; }
  # cloud-init status --wait blocks until first boot (packages, users, runcmd) is done.
  qm guest exec "$vmid" --timeout 900 -- cloud-init status --wait >/dev/null
  log "$name: cloud-init finished"
}

create_vm() {
  local name=$1 vmid=$2 ip=$3 cores=$4 mem=$5 disk=$6 extra=$7 role=$8

  if qm status "$vmid" >/dev/null 2>&1; then
    log "$name ($vmid) exists, skipping"
    return
  fi

  log "creating $name ($vmid) $ip"
  qm clone "$TEMPLATE_ID" "$vmid" --full --name "$name" --storage "$STORAGE" >/dev/null
  qm set "$vmid" --cores "$cores" --memory "$mem" --onboot 0 \
    --tags "cka-lab;$role" --description "CKA lab $role node $name ($ip). Built by cka-lab/infra." \
    --cicustom "user=$SNIPPETS_STORAGE:snippets/cka-$name.yaml" >/dev/null
  qm resize "$vmid" scsi0 "${disk}G" >/dev/null

  if [[ $role == jump ]]; then
    # eth0 on your LAN (DHCP), eth1 on the isolated lab network.
    qm set "$vmid" --net0 "virtio,bridge=$UPLINK_BRIDGE" --ipconfig0 ip=dhcp \
      --net1 "virtio,bridge=$LAB_BRIDGE" --ipconfig1 "ip=$ip/24" >/dev/null
  else
    qm set "$vmid" --net0 "virtio,bridge=$LAB_BRIDGE" --ipconfig0 "ip=$ip/24,gw=$LAB_GW" \
      --nameserver "$LAB_GW" --searchdomain "$LAB_DOMAIN" >/dev/null
  fi

  if (( extra > 0 )); then
    # Blank data disk; the storage lab has you partition, format and export it.
    qm set "$vmid" --scsi1 "$STORAGE:$extra,iothread=1,discard=on" >/dev/null
  fi
}

build() {
  local name vmid ip cores mem disk extra role created=()

  while read -r name vmid ip cores mem disk extra role; do
    qm status "$vmid" >/dev/null 2>&1 || created+=("$vmid:$name")
    create_vm "$name" "$vmid" "$ip" "$cores" "$mem" "$disk" "$extra" "$role"
  done < <(vms)

  (( ${#created[@]} )) || { log "nothing to build"; return; }

  # The jump host first: it is every node's gateway and DNS server.
  while read -r name vmid _ _ _ _ _ role; do
    [[ $role == jump && " ${created[*]} " == *" $vmid:$name "* ]] || continue
    qm start "$vmid"; wait_for_cloud_init "$vmid" "$name"
  done < <(vms)

  local pids=()
  while read -r name vmid _ _ _ _ _ role; do
    [[ $role != jump && " ${created[*]} " == *" $vmid:$name "* ]] || continue
    qm start "$vmid"
    wait_for_cloud_init "$vmid" "$name" & pids+=($!)
  done < <(vms)
  for p in "${pids[@]}"; do wait "$p"; done

  # Clean, powered-off snapshot of every new VM: `lab reset base` returns here.
  for entry in "${created[@]}"; do
    vmid=${entry%%:*}; name=${entry#*:}
    qm shutdown "$vmid" --timeout 120 >/dev/null
    qm snapshot "$vmid" base --description "Bare Ubuntu 24.04, before any lab (built $(date -u +%F))" >/dev/null
    log "$name: snapshot base"
  done
  while read -r name vmid _ _ _ _ _ role; do
    [[ $role == jump ]] && qm start "$vmid"
  done < <(vms)
  sleep 20
  while read -r name vmid _ _ _ _ _ role; do
    [[ $role != jump ]] && qm start "$vmid"
  done < <(vms)
  log "lab is up"
}

destroy() {
  local ids
  ids=$(vms | awk '{print $2}' | xargs)
  read -rp "Destroy lab VMs $ids and all their snapshots? [y/N] " ok
  [[ $ok == y ]] || exit 1
  for vmid in $ids; do
    qm status "$vmid" >/dev/null 2>&1 || continue
    qm stop "$vmid" >/dev/null 2>&1 || true
    qm destroy "$vmid" --purge >/dev/null
    log "destroyed $vmid"
  done
}

case ${1:-} in
  --destroy) destroy ;;
  "") build ;;
  *) echo "usage: $0 [--destroy]" >&2; exit 2 ;;
esac
