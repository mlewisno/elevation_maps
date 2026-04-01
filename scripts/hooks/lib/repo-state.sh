#!/usr/bin/env bash
#
# repo-state.sh - Shared library for detecting dirty repository state
#
# Provides reusable functions for checking uncommitted changes, staged files,
# untracked files, and stale branches. Used by:
# - dirty-check.sh validator (pre-push warning)
# - session-audit.sh (Claude Code session start)
#
# Usage:
#   source scripts/hooks/lib/repo-state.sh
#
#   # Check for any dirty state
#   if has_dirty_state; then
#     echo "Repo has uncommitted changes"
#   fi
#
#   # Get specific file lists (newline-separated)
#   modified=$(get_modified_files)
#   staged=$(get_staged_files)
#   untracked=$(get_untracked_files)
#
#   # Get stale branches (no commits in N days)
#   stale=$(get_stale_branches 30)
#
# Can also be run directly:
#   ./repo-state.sh              # Print dirty state summary
#   ./repo-state.sh --json       # Output as JSON
#   ./repo-state.sh --is-dirty   # Exit 0 if dirty, 1 if clean
#   ./repo-state.sh --help       # Show usage

# Minimal set options for portability (same as change-size.sh)
set -o nounset 2>/dev/null || true

# Get unstaged modifications to tracked files (newline-separated paths)
get_modified_files() {
    git diff --name-only 2>/dev/null
}

# Get staged but not yet committed files (newline-separated paths)
get_staged_files() {
    git diff --cached --name-only 2>/dev/null
}

# Get untracked files, respecting .gitignore (newline-separated paths)
get_untracked_files() {
    git ls-files --others --exclude-standard 2>/dev/null
}

# Get branches with no commits in N days (default 30)
# Output: "branch_name (Nd)" per line
get_stale_branches() {
    local days="${1:-30}"
    local now
    now=$(date +%s)
    local cutoff=$((now - days * 86400))

    git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/heads/ 2>/dev/null | \
        while read -r branch epoch; do
            # Skip current branch and main/master
            if [[ "$branch" == "main" || "$branch" == "master" ]]; then
                continue
            fi
            if [[ -n "$epoch" && "$epoch" -lt "$cutoff" ]]; then
                local age_days=$(( (now - epoch) / 86400 ))
                echo "$branch (${age_days}d)"
            fi
        done
}

# Count files in a newline-separated list (handles empty strings)
_count_lines() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo 0
    else
        echo "$input" | wc -l | tr -d ' '
    fi
}

# Returns 0 if any dirty state exists, 1 if clean
has_dirty_state() {
    local modified staged untracked
    modified=$(get_modified_files)
    staged=$(get_staged_files)
    untracked=$(get_untracked_files)

    [[ -n "$modified" || -n "$staged" || -n "$untracked" ]]
}

# Get last commit info: "TIME_AGO - SUBJECT"
get_last_commit_info() {
    local epoch subject now diff_secs
    epoch=$(git log -1 --format='%ct' 2>/dev/null) || return
    subject=$(git log -1 --format='%s' 2>/dev/null) || return
    now=$(date +%s)
    diff_secs=$((now - epoch))

    local time_ago
    if [[ $diff_secs -lt 60 ]]; then
        time_ago="just now"
    elif [[ $diff_secs -lt 3600 ]]; then
        time_ago="$((diff_secs / 60))m ago"
    elif [[ $diff_secs -lt 86400 ]]; then
        time_ago="$((diff_secs / 3600))h ago"
    else
        time_ago="$((diff_secs / 86400))d ago"
    fi

    echo "${time_ago} - \"${subject}\""
}

# Get current repo name and branch
get_repo_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null
}

get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Output all state as JSON
get_state_json() {
    local modified staged untracked stale
    modified=$(get_modified_files)
    staged=$(get_staged_files)
    untracked=$(get_untracked_files)
    stale=$(get_stale_branches 30)

    local mod_count stg_count unt_count stale_count is_dirty
    mod_count=$(_count_lines "$modified")
    stg_count=$(_count_lines "$staged")
    unt_count=$(_count_lines "$untracked")
    stale_count=$(_count_lines "$stale")

    if has_dirty_state; then
        is_dirty="true"
    else
        is_dirty="false"
    fi

    # Convert newline lists to JSON arrays
    _to_json_array() {
        local input="$1"
        if [[ -z "$input" ]]; then
            echo "[]"
        else
            echo "$input" | awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}'
        fi
    }

    cat <<EOF
{
  "repo": "$(get_repo_name)",
  "branch": "$(get_current_branch)",
  "is_dirty": $is_dirty,
  "modified_count": $mod_count,
  "staged_count": $stg_count,
  "untracked_count": $unt_count,
  "stale_branch_count": $stale_count,
  "modified": $(_to_json_array "$modified"),
  "staged": $(_to_json_array "$staged"),
  "untracked": $(_to_json_array "$untracked"),
  "stale_branches": $(_to_json_array "$stale"),
  "last_commit": "$(get_last_commit_info)"
}
EOF
}

# CLI interface when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --is-dirty)
            if has_dirty_state; then
                exit 0
            else
                exit 1
            fi
            ;;
        --json)
            get_state_json
            ;;
        --help|-h)
            echo "Usage: repo-state.sh [OPTION]"
            echo ""
            echo "Detect dirty repository state."
            echo ""
            echo "Options:"
            echo "  (none)       Print dirty state summary"
            echo "  --is-dirty   Exit 0 if dirty, 1 if clean"
            echo "  --json       Output all state as JSON"
            echo "  --help       Show this help"
            ;;
        *)
            # Default: print summary
            modified=$(get_modified_files)
            staged=$(get_staged_files)
            untracked=$(get_untracked_files)

            if [[ -z "$modified" && -z "$staged" && -z "$untracked" ]]; then
                echo "Clean"
            else
                [[ -n "$modified" ]] && echo "Modified: $modified"
                [[ -n "$staged" ]] && echo "Staged: $staged"
                [[ -n "$untracked" ]] && echo "Untracked ($(_count_lines "$untracked") files)"
            fi
            ;;
    esac
fi
