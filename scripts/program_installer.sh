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
NAMES=(); CMDS=()
while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    NAMES+=("${entry%%|*}")
    CMDS+=("${entry#*|}")
done < <(get_commands "$SECTION" "$CONFIG")

if [[ ${#NAMES[@]} -eq 0 ]]; then
    echo "No programs defined in [$SECTION]." >&2
    exit 1
fi

# ── Short descriptions shown beside each program (optional per program) ──────────
declare -A DESC=(
    [mc]="File manager"
    [htop]="Process viewer"
    [zip]="Create zip archives"
    [unzip]="Extract zip archives"
    [glow]="Markdown reader"
    [claude]="Claude Code CLI"
    [docker]="Container engine"
    [prometheus-node-exporter]="Prometheus Node Exporter (:9100)"
)

# ── Split into installed (locked) and installable ────────────────────────────────
# Installed programs are shown as a locked list marked with * — they cannot be
# toggled off, because a dialog checklist row has no read-only state, so we simply
# do not present installed programs as checkboxes at all.
AVAIL_NAMES=()
installed_list=""
installed_count=0
for name in "${NAMES[@]}"; do
    if command -v "$name" &>/dev/null; then
        d="${DESC[$name]:-}"
        if [[ -n "$d" ]]; then
            installed_list+="  * ${name} — ${d}"$'\n'
        else
            installed_list+="  * ${name}"$'\n'
        fi
        installed_count=$(( installed_count + 1 ))
    else
        AVAIL_NAMES+=("$name")
    fi
done

# ── Terminal size ────────────────────────────────────────────────────────────────
term_lines=$(tput lines 2>/dev/null || echo 24)
term_cols=$(tput cols 2>/dev/null || echo 80)
box_w=70
(( box_w > term_cols - 2 )) && box_w=$(( term_cols - 2 ))

# ── Everything already installed ─────────────────────────────────────────────────
if [[ ${#AVAIL_NAMES[@]} -eq 0 ]]; then
    msg_h=$(( installed_count + 6 ))
    (( msg_h > term_lines - 1 )) && msg_h=$(( term_lines - 1 ))
    dialog --title "Unix Program Installer" \
        --msgbox "All programs are already installed:"$'\n\n'"${installed_list}" \
        "$msg_h" "$box_w"
    clear
    exit 0
fi

# ── Build checklist of installable programs (all unchecked) ──────────────────────
ITEMS=()
for name in "${AVAIL_NAMES[@]}"; do
    ITEMS+=("$name" "${DESC[$name]:-}" "off")
done

prompt="Space toggles, Enter confirms."
if (( installed_count > 0 )); then
    prompt+=$'\n\n'"Already installed (locked):"$'\n'"${installed_list}"
fi

# ── Size the checklist to the content, capped to the terminal ────────────────────
list_h=${#AVAIL_NAMES[@]}
box_h=$(( list_h + installed_count + 9 ))
if (( box_h > term_lines - 1 )); then
    box_h=$(( term_lines - 1 ))
    list_h=$(( box_h - installed_count - 9 ))
    (( list_h < 1 )) && list_h=1
fi

# ── Show the checklist ───────────────────────────────────────────────────────────
selected=$(dialog --stdout \
    --title "Unix Program Installer" \
    --checklist "$prompt" \
    "$box_h" "$box_w" "$list_h" \
    "${ITEMS[@]}") || { clear; echo "Cancelled — no changes."; exit 0; }

clear

if [[ -z "$selected" ]]; then
    echo "Nothing selected."
    exit 0
fi

# ── Install ticked programs (the checklist only offered not-installed ones) ──────
TO_INSTALL=()
for name in $selected; do
    name="${name%\"}"; name="${name#\"}"          # strip quotes if present
    TO_INSTALL+=("$name")
done

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
