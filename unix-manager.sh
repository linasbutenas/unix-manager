#!/usr/bin/env bash
set -euo pipefail

# ── Dependency check ───────────────────────────────────────────────────────────
if ! command -v dialog &>/dev/null; then
    echo "Error: 'dialog' is required but not installed."
    echo "Install with: sudo apt install dialog  (Debian/Ubuntu)"
    echo "              sudo dnf install dialog   (Fedora)"
    exit 1
fi

# ── Config resolution ──────────────────────────────────────────────────────────
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager/config.conf"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config not found: $CONFIG"
    echo ""
    read -rp "Create example config there? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
        cat > "$CONFIG" << 'CONF'
[Docker]
ps    = docker ps -a

[Git]
st    = git status
log   = git log --oneline -10
push  = git push origin HEAD

[System]
df    = df -h
mem   = free -h
top   = htop
CONF
        echo "Created: $CONFIG"
        echo "Edit it, then rerun the launcher."
    fi
    exit 0
fi

# ── INI parser helpers ─────────────────────────────────────────────────────────

get_sections() {
    grep -E '^\[.+\]' "$CONFIG" | sed 's/^\[\(.*\)\]$/\1/'
}

get_commands() {
    local section="$1"
    local in_section=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            [[ "${BASH_REMATCH[1]}" == "$section" ]] && in_section=1 || in_section=0
            continue
        fi
        [[ $in_section -eq 0 ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local name cmd
            name="${BASH_REMATCH[1]}"
            cmd="${BASH_REMATCH[2]}"
            name="${name#"${name%%[! ]*}"}"; name="${name%"${name##*[! ]}"}"
            cmd="${cmd#"${cmd%%[! ]*}"}";   cmd="${cmd%"${cmd##*[! ]}"}"
            echo "${name}|${cmd}"
        fi
    done < "$CONFIG"
}

# ── Build flat tree menu ───────────────────────────────────────────────────────
# MENU_ITEMS: flat array of (tag desc) pairs for dialog
# CMD_MAP:    CMD_MAP[tag] = command to run, or "__GROUP__" for headers

declare -a MENU_ITEMS
declare -a CMD_MAP

build_menu() {
    MENU_ITEMS=()
    CMD_MAP=("")   # index 0 unused; tags start at 1

    local index=1
    while IFS= read -r section; do
        MENU_ITEMS+=("$index" "  ▶  ${section}")
        CMD_MAP+=("__GROUP__")
        ((index++))

        while IFS= read -r entry; do
            local name="${entry%%|*}"
            local cmd="${entry#*|}"
            MENU_ITEMS+=("$index" "       ${name}  →  ${cmd}")
            CMD_MAP+=("$cmd")
            ((index++))
        done < <(get_commands "$section")
    done < <(get_sections)
}

# ── Run a command ──────────────────────────────────────────────────────────────
run_command() {
    local cmd="$1"
    clear
    echo "┌────────────────────────────────────────────────────────────┐"
    printf  "│ \$ %-58s│\n" "$cmd"
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""
    eval "$cmd"
    local exit_code=$?
    echo ""
    echo "────────────────────────────────────────────────────────────"
    [[ $exit_code -eq 0 ]] && echo "Done (exit 0)" || echo "Exit code: $exit_code"
    echo "Press Enter to return to menu..."
    read -r
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
    build_menu

    if [[ ${#MENU_ITEMS[@]} -eq 0 ]]; then
        dialog --title "Unix Manager" --msgbox "No commands found in:\n$CONFIG" 7 55
        exit 1
    fi

    choice=$(dialog --stdout \
        --title "Unix Manager" \
        --cancel-label "Quit" \
        --menu "$(basename "$CONFIG")" \
        40 120 30 \
        "${MENU_ITEMS[@]}") || { clear; exit 0; }

    cmd="${CMD_MAP[$choice]}"
    [[ "$cmd" == "__GROUP__" ]] && continue

    run_command "$cmd"
done
