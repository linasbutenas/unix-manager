#!/usr/bin/env bash
set -euo pipefail

# Adds the host user's SSH public key to a Multipass VM, so the VM stays
# reachable with plain ssh even if Multipass' own key is lost, and keeps a copy
# of the VM's authorized_keys on the host for recovery.
#
# Usage: add_host_ssh_key.sh [vm-name] [public-key-file]

VM="${1:-}"
KEY="${2:-}"

if [[ -z "$VM" ]]; then
    multipass list
    read -rp "VM name: " VM
fi
[[ -n "$VM" ]] || { echo "Error: no VM name given."; exit 1; }

# ── Resolve the public key ─────────────────────────────────────────────────────
if [[ -z "$KEY" ]]; then
    for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
        [[ -f "$candidate" ]] && { KEY="$candidate"; break; }
    done
fi

# A missing host key is not fatal: this step hardens a VM, it must never fail a
# freshly completed launch.
if [[ -z "$KEY" || ! -f "$KEY" ]]; then
    echo "Warning: no SSH public key found (~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)."
    echo "         Create one with 'ssh-keygen -t ed25519', then re-run: Multipass → ssh key"
    exit 0
fi
ssh-keygen -lf "$KEY" >/dev/null || { echo "Error: $KEY is not a valid public key."; exit 1; }

# ── The VM has to be running for exec to work ─────────────────────────────────
# `|| true` matters: with `set -e` + `pipefail` a failing `multipass info`
# (unknown VM) would abort the script before the check below can report it.
state=$(multipass info "$VM" --format csv 2>/dev/null | awk -F, 'NR==2 {print $2}' || true)
if [[ -z "$state" ]]; then
    echo "Error: no such VM: $VM"
    exit 1
fi
if [[ "$state" != "Running" ]]; then
    echo "Error: VM '$VM' is $state. Start it first: multipass start $VM"
    exit 1
fi

# ── Append the key inside the VM (idempotent) ────────────────────────────────
echo "Adding $(ssh-keygen -lf "$KEY" | awk '{print $2}') to $VM..."
multipass exec "$VM" -- bash -c '
    set -euo pipefail
    key="$1"
    ak="$HOME/.ssh/authorized_keys"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$ak"
    chmod 600 "$ak"
    if grep -qxF -- "$key" "$ak"; then
        echo "  Key already present in $ak"
    else
        printf "%s\n" "$key" >> "$ak"
        echo "  Key appended to $ak"
    fi
' _ "$(cat "$KEY")"

# ── Keep a host-side copy so a wiped authorized_keys can be restored ─────────
backup_dir="$HOME/.mp_$VM"
mkdir -p "$backup_dir"
multipass exec "$VM" -- cat /home/ubuntu/.ssh/authorized_keys > "$backup_dir/authorized_keys"
chmod 600 "$backup_dir/authorized_keys"

ip=$(multipass info "$VM" --format csv 2>/dev/null | awk -F, 'NR==2 {print $3}' || true)
echo "  Recovery copy → $backup_dir/authorized_keys"
echo "  Direct access → ssh ubuntu@${ip}"
