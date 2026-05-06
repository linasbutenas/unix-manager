#!/usr/bin/env bash
set -euo pipefail

# ── Requirements check ─────────────────────────────────────────────────────────
MISSING=()

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: bash 4+ is required (running ${BASH_VERSION})."
    exit 1
fi

command -v git  &>/dev/null || MISSING+=("git")
command -v curl &>/dev/null || MISSING+=("curl")

if ! command -v dialog &>/dev/null; then
    echo "'dialog' is not installed. Installing..."
    sudo apt-get install -y dialog || { echo "Error: failed to install dialog."; exit 1; }
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Error: missing required tools: ${MISSING[*]}"
    echo "Install with: sudo apt install ${MISSING[*]}"
    exit 1
fi

REPO_URL="https://bitbucket.org/linasbprojects/unix-manager"
REPO_DIR="$HOME/.local/share/unix-manager"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Ensure we always run from the canonical repo location ─────────────────────
if [[ "$SCRIPT_DIR" != "$REPO_DIR" ]]; then
    if [[ -d "$REPO_DIR/.git" ]]; then
        echo "Updating repo at $REPO_DIR..."
        git -C "$REPO_DIR" pull
    else
        [[ -d "$REPO_DIR" ]] && rm -rf "$REPO_DIR"
        REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")
        echo "Cloning repo to $REPO_DIR..."
        git clone "${REMOTE:-$REPO_URL}" "$REPO_DIR"
    fi
    exec bash "$REPO_DIR/install.sh"
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"

echo "Installing unix-manager..."

# ── Install script ─────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/unix-manager.sh" "$BIN_DIR/unix-manager"
chmod +x "$BIN_DIR/unix-manager"
echo "  Script  → $BIN_DIR/unix-manager"

# ── Install config (always overwrite global, never touch local) ───────────────
mkdir -p "$CONFIG_DIR"
cp "$REPO_DIR/unix-manager.conf" "$CONFIG_FILE"
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
cp "$REPO_DIR/scripts/"* "$CONFIG_DIR/scripts/"
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
