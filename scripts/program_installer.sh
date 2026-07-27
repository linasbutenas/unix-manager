#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for the [Unix Program Installer] group.
# Reads the program list from config.conf, shows a checklist with already-
# installed programs marked [X], and installs the ones the user ticks.

if ! command -v dialog &>/dev/null; then
    echo "Error: 'dialog' is required but not installed." >&2
    exit 1
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/unix-manager"
CONFIG="$CONFIG_DIR/config.conf"
SECTION="Unix Program Installer"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config not found: $CONFIG" >&2
    exit 1
fi

# ── Parse "name|command" pairs from a section ────────────────────────────────────
get_commands() {
    local section="$1" file="$2" in_section=0 line
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
            name="${BASH_REMATCH[1]}"; cmd="${BASH_REMATCH[2]}"
            name="${name#"${name%%[! ]*}"}"; name="${name%"${name##*[! ]}"}"
            cmd="${cmd#"${cmd%%[! ]*}"}";   cmd="${cmd%"${cmd##*[! ]}"}"
            echo "${name}|${cmd}"
        fi
    done < "$file"
}

# ── Build program list ───────────────────────────────────────────────────────────
declare -a NAMES CMDS
while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    NAMES+=("${entry%%|*}")
    CMDS+=("${entry#*|}")
done < <(get_commands "$SECTION" "$CONFIG")

if [[ ${#NAMES[@]} -eq 0 ]]; then
    echo "No programs defined in [$SECTION]." >&2
    exit 1
fi

# ── Detect installed status, build checklist items ───────────────────────────────
declare -a ITEMS
declare -A INSTALLED
for name in "${NAMES[@]}"; do
    if command -v "$name" &>/dev/null; then
        INSTALLED["$name"]=1
        ITEMS+=("$name" "installed" "on")
    else
        INSTALLED["$name"]=0
        ITEMS+=("$name" "not installed" "off")
    fi
done

# ── Size the checklist to the item count, capped to the terminal ─────────────────
term_lines=$(tput lines 2>/dev/null || echo 24)
term_cols=$(tput cols 2>/dev/null || echo 80)
num=${#NAMES[@]}
list_h=$num
box_h=$(( num + 8 ))
if (( box_h > term_lines - 1 )); then
    box_h=$(( term_lines - 1 ))
    list_h=$(( box_h - 8 ))
fi
box_w=70
(( box_w > term_cols - 2 )) && box_w=$(( term_cols - 2 ))

# ── Show the checklist ───────────────────────────────────────────────────────────
selected=$(dialog --stdout \
    --title "Unix Program Installer" \
    --checklist "Space toggles, Enter confirms.  [X] = already installed." \
    "$box_h" "$box_w" "$list_h" \
    "${ITEMS[@]}") || { clear; echo "Cancelled — no changes."; exit 0; }

clear

if [[ -z "$selected" ]]; then
    echo "Nothing selected."
    exit 0
fi

# ── Install ticked programs that aren't already installed ────────────────────────
declare -a TO_INSTALL
for name in $selected; do
    name="${name%\"}"; name="${name#\"}"          # strip quotes if present
    [[ "${INSTALLED[$name]:-0}" == "1" ]] && continue
    TO_INSTALL+=("$name")
done

if [[ ${#TO_INSTALL[@]} -eq 0 ]]; then
    echo "Selected programs are already installed. Nothing to do."
    exit 0
fi

fail=0
for name in "${TO_INSTALL[@]}"; do
    for i in "${!NAMES[@]}"; do
        if [[ "${NAMES[$i]}" == "$name" ]]; then
            echo "────────────────────────────────────────────────────────────"
            echo "Installing ${name}..."
            echo "────────────────────────────────────────────────────────────"
            if eval "${CMDS[$i]}"; then
                echo "${name}: OK"
            else
                echo "${name}: FAILED" >&2
                fail=1
            fi
            echo ""
            break
        fi
    done
done

(( fail )) && echo "Some installs failed." || echo "All selected programs installed."
exit "$fail"
