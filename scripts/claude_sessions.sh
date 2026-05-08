#!/usr/bin/env bash
set -euo pipefail

PROJECTS_DIR="$HOME/.claude/projects"

if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "No Claude projects found at $PROJECTS_DIR"
    exit 0
fi

echo "Claude Projects & Sessions"
echo "══════════════════════════════════════════════════════════════"

for project_dir in "$PROJECTS_DIR"/*/; do
    [[ -d "$project_dir" ]] || continue

    # Convert dir name back to path: -home-ubuntu-projects-tui1 → /home/ubuntu/projects/tui1
    dir_name=$(basename "$project_dir")
    project_path=$(echo "$dir_name" | sed 's|^-|/|; s|-\([^-]\)| \1|g; s| |/|g')

    echo ""
    echo "  ▶ $project_path"
    echo "  ─────────────────────────────────────────────────────────"

    shopt -s nullglob
    sessions=("$project_dir"*.jsonl)
    shopt -u nullglob
    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo "    (no sessions)"
        continue
    fi

    for session_file in "$project_dir"*.jsonl; do
        [[ -f "$session_file" ]] || continue
        session_id=$(basename "$session_file" .jsonl)

        # Extract earliest timestamp from session file
        ts=$(grep -m1 '"timestamp"' "$session_file" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 || echo "")
        if [[ -n "$ts" ]]; then
            date_str=$(date -d "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts")
        else
            date_str="unknown date"
        fi
        version=""

        line_count=$(wc -l < "$session_file")
        echo "    $session_id  │  $date_str  │  $line_count messages"
    done
done

echo ""
echo "══════════════════════════════════════════════════════════════"
