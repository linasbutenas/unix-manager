#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"

echo "Installing unix-manager..."

# ── Install script ─────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp unix-manager.sh "$BIN_DIR/unix-manager"
chmod +x "$BIN_DIR/unix-manager"
echo "  Script  → $BIN_DIR/unix-manager"

# ── Install config (always overwrite global, never touch local) ───────────────
mkdir -p "$CONFIG_DIR"
cp unix-manager.conf "$CONFIG_FILE"
echo "  Config  → $CONFIG_FILE (updated)"

LOCAL_FILE="$CONFIG_DIR/config_local.conf"
if [[ ! -f "$LOCAL_FILE" ]]; then
    cat > "$LOCAL_FILE" << 'EOF'
# Local commands — this file is never overwritten by install.sh
# Add your personal groups and commands here.
#
# [My Group]
# hello = echo "Hello, world!"
EOF
    echo "  Local   → $LOCAL_FILE (created)"
else
    echo "  Local   → $LOCAL_FILE (already exists, skipping)"
fi

# ── Install scripts ────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR/scripts"
cp scripts/* "$CONFIG_DIR/scripts/"
chmod +x "$CONFIG_DIR/scripts/"*
echo "  Scripts → $CONFIG_DIR/scripts/"

# ── Shell integration (PATH + alias) ──────────────────────────────────────────
BASHRC="$HOME/.bashrc"
MARKER="# unix-manager"

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    {
        echo ""
        echo "$MARKER"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "alias um='unix-manager'"
    } >> "$BASHRC"
    echo "  Shell   → added PATH + alias 'um' to $BASHRC"
else
    echo "  Shell   → $BASHRC already configured (skipping)"
fi

echo ""
echo "Done. Open a new terminal (or run: source ~/.bashrc) then use: um"
