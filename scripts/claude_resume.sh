#!/usr/bin/env bash
set -euo pipefail

PROJECTS_DIR="$HOME/.claude/projects"

if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "No Claude projects found at $PROJECTS_DIR"
    exit 0
fi

# Build dialog menu items: tag = session_id, description = "project | date | messages"
declare -a MENU_ITEMS

for project_dir in "$PROJECTS_DIR"/*/; do
    [[ -d "$project_dir" ]] || continue

    dir_name=$(basename "$project_dir")
    project_path=$(echo "$dir_name" | sed 's|^-|/|; s|-\([^-]\)| \1|g; s| |/|g')

    shopt -s nullglob
    sessions=("$project_dir"*.jsonl)
    shopt -u nullglob
    [[ ${#sessions[@]} -eq 0 ]] && continue

    for session_file in "${sessions[@]}"; do
        session_id=$(basename "$session_file" .jsonl)

        ts=$(grep -m1 '"timestamp"' "$session_file" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 || echo "")
        if [[ -n "$ts" ]]; then
            date_str=$(date -d "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts")
        else
            date_str="unknown"
        fi

        line_count=$(wc -l < "$session_file")
        MENU_ITEMS+=("$session_id" "$project_path  │  $date_str  │  $line_count msgs")
    done
done

if [[ ${#MENU_ITEMS[@]} -eq 0 ]]; then
    dialog --msgbox "No Claude sessions found." 6 40
    exit 0
fi

choice=$(dialog --stdout \
    --title "Resume Claude Session" \
    --cancel-label "Cancel" \
    --menu "Select a session to resume:" \
    30 110 20 \
    "${MENU_ITEMS[@]}") || exit 0

clear
exec claude --resume "$choice"
