#!/usr/bin/env bash
set -euo pipefail

echo "Removing old unix-manager / lb_launcher installations..."

# ── Binaries ──────────────────────────────────────────────────────────────────
for bin in "$HOME/.local/bin/lb_launcher"; do
    if [[ -f "$bin" ]]; then
        rm -f "$bin"
        echo "  Removed → $bin"
    fi
done

# ── Config dirs (keep config_local.conf) ──────────────────────────────────────
for dir in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/lb_launcher"; do
    if [[ -d "$dir" ]]; then
        local_conf="$dir/config_local.conf"
        if [[ -f "$local_conf" ]]; then
            tmp=$(mktemp)
            cp "$local_conf" "$tmp"
            rm -rf "$dir"
            mkdir -p "$dir"
            mv "$tmp" "$local_conf"
            echo "  Removed → $dir (config_local.conf preserved)"
        else
            rm -rf "$dir"
            echo "  Removed → $dir"
        fi
    fi
done

# ── ~/.bashrc entries ─────────────────────────────────────────────────────────
BASHRC="$HOME/.bashrc"
for marker in "# lb_launcher"; do
    if grep -qF "$marker" "$BASHRC" 2>/dev/null; then
        # Remove the marker line and the two lines that follow it
        grep -n -F "$marker" "$BASHRC" | while IFS=: read -r lineno _; do
            sed -i "${lineno},$((lineno + 2))d" "$BASHRC"
        done
        echo "  Cleaned → $BASHRC ($marker block removed)"
    fi
done

echo ""
echo "Uninstall complete."
