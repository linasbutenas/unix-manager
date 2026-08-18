#!/usr/bin/env bash
set -euo pipefail

VERSION="1.2.6"

# ── Dependency check ───────────────────────────────────────────────────────────
if ! command -v dialog &>/dev/null; then
    echo "Error: 'dialog' is required but not installed."
    echo "Install with: sudo apt install dialog  (Debian/Ubuntu)"
    echo "              sudo dnf install dialog   (Fedora)"
    exit 1
fi

# ── Config resolution ──────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager"
CONFIG="$CONFIG_DIR/config.conf"
CONFIG_LOCAL="$CONFIG_DIR/config_local.conf"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config not found: $CONFIG"
    echo "Run install.sh first."
    exit 1
fi

# ── INI parser helpers ─────────────────────────────────────────────────────────

get_sections() {
    local file="$1"
    grep -E '^\[.+\]' "$file" | sed 's/^\[\(.*\)\]$/\1/'
}

get_commands() {
    local section="$1"
    local file="$2"
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
    done < "$file"
}

# ── Build flat tree menu ───────────────────────────────────────────────────────
# MENU_ITEMS: flat array of (tag desc) pairs for dialog
# CMD_MAP:    CMD_MAP[tag] = command to run, or "__GROUP__" for headers

declare -a MENU_ITEMS
declare -a CMD_MAP

add_sections_from_file() {
    local file="$1"
    local label="$2"
    while IFS= read -r section; do
        MENU_ITEMS+=("$index" "  ▶  ${section}${label}")
        CMD_MAP+=("__GROUP__")
        ((index++))

        # The program installer group opens a checklist window instead of
        # listing each program as a separate menu command.
        if [[ "$section" == "Unix Program Installer" ]]; then
            local installer="$CONFIG_DIR/scripts/program_installer.sh"
            MENU_ITEMS+=("$index" "       open  →  select & install programs")
            CMD_MAP+=("bash \"$installer\"")
            ((index++))
            continue
        fi

        while IFS= read -r entry; do
            local name="${entry%%|*}"
            MENU_ITEMS+=("$index" "       ${name}")
            CMD_MAP+=("${entry#*|}")
            ((index++))
        done < <(get_commands "$section" "$file")
    done < <(get_sections "$file")
}

build_menu() {
    MENU_ITEMS=()
    CMD_MAP=("")   # index 0 unused; tags start at 1

    local index=1
    [[ -f "$CONFIG_LOCAL" ]] && add_sections_from_file "$CONFIG_LOCAL" "  [local]"
    add_sections_from_file "$CONFIG" ""
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

    # ── Size the menu to the item count, capped to the terminal ──────────────────
    term_lines=$(tput lines 2>/dev/null || echo 40)
    term_cols=$(tput cols 2>/dev/null || echo 120)
    num_items=$(( ${#MENU_ITEMS[@]} / 2 ))

    menu_h=$num_items                       # visible list rows
    box_h=$(( num_items + 7 ))              # + borders, title, prompt
    if (( box_h > term_lines - 1 )); then   # cap to terminal height
        box_h=$(( term_lines - 1 ))
        menu_h=$(( box_h - 7 ))
    fi
    box_w=120
    (( box_w > term_cols - 2 )) && box_w=$(( term_cols - 2 ))

    choice=$(dialog --stdout \
        --title "Unix Manager v${VERSION}" \
        --cancel-label "Quit" \
        --menu "config.conf + config_local.conf" \
        "$box_h" "$box_w" "$menu_h" \
        "${MENU_ITEMS[@]}") || { clear; exit 0; }

    cmd="${CMD_MAP[$choice]}"
    [[ "$cmd" == "__GROUP__" ]] && continue

    run_command "$cmd"
done
