#!/usr/bin/env bash
set -euo pipefail

# Manage a fixed set of ufw firewall rules from a checklist. Ticked = active.
# Tick to create, untick to delete; changes are confirmed before being applied.

if ! command -v dialog &>/dev/null; then
    echo "Error: 'dialog' is required but not installed." >&2
    exit 1
fi
if ! command -v ufw &>/dev/null; then
    echo "Error: 'ufw' is not installed. Install with: sudo apt install ufw" >&2
    exit 1
fi

# Managed rules. KEYS order is also the apply order for rule changes; the
# 'enabled' toggle is always applied last so a firewall is never enabled before
# its SSH/allow rules exist.
KEYS=(ssh-limit http https default-deny enabled)
declare -A LABEL=(
    [ssh-limit]="SSH rate-limited (22/tcp)"
    [http]="HTTP (80/tcp)"
    [https]="HTTPS (443/tcp)"
    [default-deny]="Default deny incoming"
    [enabled]="Firewall enabled"
)

create_cmd() {
    case "$1" in
        ssh-limit)    echo "sudo ufw limit 22/tcp" ;;
        http)         echo "sudo ufw allow 80/tcp" ;;
        https)        echo "sudo ufw allow 443/tcp" ;;
        default-deny) echo "sudo ufw default deny incoming" ;;
        enabled)      echo "sudo ufw --force enable" ;;
    esac
}
delete_cmd() {
    case "$1" in
        ssh-limit)    echo "sudo ufw delete limit 22/tcp" ;;
        http)         echo "sudo ufw delete allow 80/tcp" ;;
        https)        echo "sudo ufw delete allow 443/tcp" ;;
        default-deny) echo "sudo ufw default allow incoming" ;;
        enabled)      echo "sudo ufw disable" ;;
    esac
}

# ── Detect current state (read-only; works whether ufw is active or not) ─────────
added=$(sudo ufw show added 2>/dev/null || true)
input_policy=$(sudo grep -E '^DEFAULT_INPUT_POLICY=' /etc/default/ufw 2>/dev/null | cut -d'"' -f2 || true)
enabled_conf=$(sudo grep -E '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 || true)

is_present() {
    case "$1" in
        ssh-limit)    grep -qE 'limit (22/tcp|ssh)' <<<"$added" ;;
        http)         grep -qE 'allow 80/tcp' <<<"$added" ;;
        https)        grep -qE 'allow 443/tcp' <<<"$added" ;;
        default-deny) [[ "$input_policy" == "DROP" || "$input_policy" == "REJECT" ]] ;;
        enabled)      [[ "$enabled_conf" == "yes" ]] ;;
    esac
}

# ── Build the checklist (installed/active rules pre-ticked) ──────────────────────
ITEMS=()
for k in "${KEYS[@]}"; do
    if is_present "$k"; then
        ITEMS+=("$k" "${LABEL[$k]}" "on")
    else
        ITEMS+=("$k" "${LABEL[$k]}" "off")
    fi
done

# ── Size to the item count, capped to the terminal ───────────────────────────────
term_lines=$(tput lines 2>/dev/null || echo 24)
term_cols=$(tput cols 2>/dev/null || echo 80)
num=${#KEYS[@]}
list_h=$num
box_h=$(( num + 8 ))
if (( box_h > term_lines - 1 )); then
    box_h=$(( term_lines - 1 )); list_h=$(( box_h - 8 )); (( list_h < 1 )) && list_h=1
fi
box_w=64
(( box_w > term_cols - 2 )) && box_w=$(( term_cols - 2 ))

# ── Show the checklist ───────────────────────────────────────────────────────────
selected=$(dialog --stdout \
    --title "UFW Firewall" \
    --checklist "Ticked = active.  Tick to create, untick to delete." \
    "$box_h" "$box_w" "$list_h" \
    "${ITEMS[@]}") || { clear; echo "Cancelled — no changes."; exit 0; }

# ── Reconcile desired vs current ─────────────────────────────────────────────────
declare -A WANT=()
for t in $selected; do
    t="${t%\"}"; t="${t#\"}"
    WANT["$t"]=1
done

CREATE=(); DELETE=()
for k in "${KEYS[@]}"; do
    cur=0; is_present "$k" && cur=1
    want="${WANT[$k]:-0}"
    if [[ "$want" == "1" && "$cur" == "0" ]]; then CREATE+=("$k"); fi
    if [[ "$want" == "0" && "$cur" == "1" ]]; then DELETE+=("$k"); fi
done

if [[ ${#CREATE[@]} -eq 0 && ${#DELETE[@]} -eq 0 ]]; then
    dialog --title "UFW Firewall" --msgbox "No changes." 6 40
    clear
    exit 0
fi

# ── Confirmation summary ─────────────────────────────────────────────────────────
summary=""
for k in "${CREATE[@]}"; do summary+="  + create: ${LABEL[$k]}"$'\n'; done
for k in "${DELETE[@]}"; do summary+="  - delete: ${LABEL[$k]}"$'\n'; done

warn=""
if [[ " ${CREATE[*]} " == *" enabled "* && "${WANT[ssh-limit]:-0}" != "1" ]]; then
    warn=$'\n'"WARNING: enabling the firewall without an SSH rule may lock you"$'\n'"out of remote SSH sessions."$'\n'
fi

conf_h=$(( ${#CREATE[@]} + ${#DELETE[@]} + 10 ))
(( conf_h > term_lines - 1 )) && conf_h=$(( term_lines - 1 ))
dialog --title "UFW — confirm" \
    --yesno "Apply these changes?"$'\n\n'"${summary}${warn}" \
    "$conf_h" "$box_w" || { clear; echo "Cancelled — no changes."; exit 0; }

clear

# ── Apply (rule changes first, enable/disable last) ──────────────────────────────
fail=0
apply() {
    local desc="$1" cmd="$2"
    echo "── ${desc} ──"
    if eval "$cmd"; then echo "OK"; else echo "FAILED" >&2; fail=1; fi
    echo ""
}

for k in "${CREATE[@]}"; do
    if [[ "$k" != "enabled" ]]; then apply "create ${LABEL[$k]}" "$(create_cmd "$k")"; fi
done
for k in "${DELETE[@]}"; do
    if [[ "$k" != "enabled" ]]; then apply "delete ${LABEL[$k]}" "$(delete_cmd "$k")"; fi
done
for k in "${CREATE[@]}"; do
    if [[ "$k" == "enabled" ]]; then apply "enable firewall" "$(create_cmd enabled)"; fi
done
for k in "${DELETE[@]}"; do
    if [[ "$k" == "enabled" ]]; then apply "disable firewall" "$(delete_cmd enabled)"; fi
done

echo "── Current status ──"
sudo ufw status verbose || true
echo ""

(( fail )) && echo "Some changes failed." || echo "Done."
exit "$fail"
