#!/usr/bin/env bash
#
# session-audit.sh - Show repo state at Claude Code session start
#
# Plain text output (no ANSI colors) so Claude reads it as context.
#
# Usage:
#   ./scripts/session-audit.sh          # Print audit summary
#   ./scripts/session-audit.sh --setup  # Print settings.local.json hook config

set -euo pipefail

# --setup: print JSON config snippet and exit
if [[ "${1:-}" == "--setup" ]]; then
    cat <<'SETUP_EOF'
Add this to your .claude/settings.local.json to run the audit on session start:

{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/session-audit.sh"
          }
        ]
      }
    ]
  }
}

Also add the permission:

  "Bash(./scripts/session-audit.sh:*)"

to the "permissions.allow" array in .claude/settings.local.json.
SETUP_EOF
    exit 0
fi

# Find repo-state.sh relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="$SCRIPT_DIR/hooks/lib/repo-state.sh"

if [[ ! -f "$LIB_FILE" ]]; then
    echo "[Session Audit] Error: repo-state.sh not found at $LIB_FILE"
    exit 0  # Don't block session start
fi

# shellcheck source=/dev/null
source "$LIB_FILE"

repo=$(get_repo_name)
branch=$(get_current_branch)
last_commit=$(get_last_commit_info)

# Gather state
modified=$(get_modified_files)
staged=$(get_staged_files)
untracked=$(get_untracked_files)
stale=$(get_stale_branches 30)

# Clean repo: one-line output
if [[ -z "$modified" && -z "$staged" && -z "$untracked" && -z "$stale" ]]; then
    echo "[Session Audit] repo: $repo | branch: $branch | clean"
    echo "Last commit: $last_commit"
    exit 0
fi

# Dirty repo: detailed output
echo "[Session Audit] repo: $repo | branch: $branch"
echo ""

if [[ -n "$modified" || -n "$staged" || -n "$untracked" ]]; then
    echo "Uncommitted changes:"

    if [[ -n "$modified" ]]; then
        mod_list=$(echo "$modified" | tr '\n' ',' | sed 's/,/, /g; s/, $//')
        echo "  Modified: $mod_list"
    fi

    if [[ -n "$staged" ]]; then
        stg_list=$(echo "$staged" | tr '\n' ',' | sed 's/,/, /g; s/, $//')
        echo "  Staged: $stg_list"
    fi

    if [[ -n "$untracked" ]]; then
        unt_count=$(_count_lines "$untracked")
        if [[ "$unt_count" -le 5 ]]; then
            unt_list=$(echo "$untracked" | tr '\n' ',' | sed 's/,/, /g; s/, $//')
            echo "  Untracked: $unt_count files ($unt_list)"
        else
            unt_preview=$(echo "$untracked" | head -3 | tr '\n' ',' | sed 's/,/, /g; s/, $//')
            echo "  Untracked: $unt_count files ($unt_preview, ...)"
        fi
    fi
    echo ""
fi

if [[ -n "$stale" ]]; then
    echo "Stale branches (no commits in 30+ days):"
    echo "$stale" | while read -r line; do echo "  $line"; done
    echo ""
fi

echo "Last commit: $last_commit"
