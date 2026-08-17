#!/usr/bin/env bash
set -euo pipefail

echo "Create a local Unix user"
echo ""

# ── Username ────────────────────────────────────────────────────────────────────
read -rp "Username: " user

if [[ -z "$user" ]]; then
    echo "Error: username cannot be empty." >&2
    exit 1
fi

if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "Error: invalid username '$user'." >&2
    echo "Must start with a letter or underscore and contain only lowercase" >&2
    echo "letters, digits, underscores or hyphens." >&2
    exit 1
fi

if id "$user" &>/dev/null; then
    echo "Error: user '$user' already exists." >&2
    exit 1
fi

# ── Create user ─────────────────────────────────────────────────────────────────
sudo useradd -m -s /bin/bash "$user"
echo "Created user '$user' with home directory and bash shell."

# ── Supplementary groups ────────────────────────────────────────────────────────
read -rp "Supplementary groups (comma-separated, optional): " groups
if [[ -n "$groups" ]]; then
    IFS=',' read -ra group_list <<< "$groups"
    for g in "${group_list[@]}"; do
        g="${g#"${g%%[! ]*}"}"; g="${g%"${g##*[! ]}"}"   # trim whitespace
        [[ -z "$g" ]] && continue
        sudo usermod -aG "$g" "$user"
        echo "Added '$user' to group '$g'."
    done
fi

# ── Grant sudo ──────────────────────────────────────────────────────────────────
read -rp "Grant sudo? [y/N] " grant_sudo
if [[ "${grant_sudo,,}" == "y" ]]; then
    sudo usermod -aG sudo "$user"
    echo "Granted sudo to '$user'."
fi

# ── Copy SSH authorized_keys (optional) ──────────────────────────────────────────
read -rp "Copy your ~/.ssh/authorized_keys to '$user'? [y/N] " copy_keys
if [[ "${copy_keys,,}" == "y" ]]; then
    src="$HOME/.ssh/authorized_keys"
    if [[ -f "$src" ]]; then
        new_home=$(getent passwd "$user" | cut -d: -f6)
        new_home="${new_home:-/home/$user}"
        sudo mkdir -p "$new_home/.ssh"
        sudo cp "$src" "$new_home/.ssh/authorized_keys"
        sudo chown -R "$user":"$user" "$new_home/.ssh"
        sudo chmod 700 "$new_home/.ssh"
        sudo chmod 600 "$new_home/.ssh/authorized_keys"
        echo "Copied authorized_keys to $new_home/.ssh/ and set ownership."
    else
        echo "No authorized_keys found at $src — skipping."
    fi
fi

# ── Password ────────────────────────────────────────────────────────────────────
echo ""
echo "Set a password for '$user':"
sudo passwd "$user"

# ── Summary ─────────────────────────────────────────────────────────────────────
echo ""
echo "Done. Current membership:"
id "$user"
