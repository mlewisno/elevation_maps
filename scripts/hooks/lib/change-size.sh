#!/usr/bin/env bash
#
# change-size.sh - Shared library for calculating change sizes
#
# Provides deterministic change size calculation used by:
# - diff-size-check.sh validator
# - /feature skill (size-conditional PR review)
# - Any other tool needing to assess change size
#
# Usage:
#   source scripts/hooks/lib/change-size.sh
#
#   # Get total lines added (production code only)
#   lines=$(get_added_lines)
#
#   # Check if change is "large" (exceeds threshold)
#   if is_large_change; then
#     echo "This is a large change"
#   fi
#
#   # Get the threshold value
#   threshold=$(get_size_threshold)
#
# Can also be run directly:
#   ./change-size.sh              # Returns lines added to stdout
#   ./change-size.sh --is-large   # Exit 0 if large, 1 if small
#   ./change-size.sh --threshold  # Print threshold value
#   ./change-size.sh --json       # Output as JSON

# Note: Intentionally minimal set options for portability
# -e omitted: Allow functions to return non-zero exit codes
# -u omitted: Some git commands may reference undefined vars
# pipefail omitted: Avoid issues with pipe exit codes
set -o nounset 2>/dev/null || true

# Load config if available (for DIFF_LIMIT)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Default threshold
DIFF_LIMIT="${DIFF_LIMIT:-150}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Test file patterns to exclude from "production" line counts
# These patterns match common test file conventions across languages
# Format: space-separated list for use with git pathspec
# Note: Use ':(exclude)' syntax instead of ':!' for patterns with special chars
TEST_EXCLUSIONS="':(exclude)spec/' ':(exclude)test/' ':(exclude)tests/' ':(exclude)**/__tests__/' ':(exclude)*_test.go' ':(exclude)*_spec.rb' ':(exclude)*.test.ts' ':(exclude)*.test.tsx' ':(exclude)*.test.js' ':(exclude)*.test.jsx' ':(exclude)*.spec.ts' ':(exclude)*.spec.tsx' ':(exclude)*.spec.js' ':(exclude)*.spec.jsx' ':(exclude)*_test.py' ':(exclude)test_*.py' ':(exclude)*Test.java' ':(exclude)*_test.rs'"

# Get the configured size threshold
get_size_threshold() {
    echo "$DIFF_LIMIT"
}

# Count added lines in staged changes, excluding test files
# Returns: number of lines added (production code only)
get_staged_added_lines() {
    eval "git diff --cached --numstat -- $TEST_EXCLUSIONS" 2>/dev/null | \
        awk '{ sum += $1 } END { print sum+0 }'
}

# Count added lines comparing branch to main, excluding test files
# Returns: number of lines added (production code only)
get_branch_added_lines() {
    local base="${1:-main}"
    eval "git diff ${base}...HEAD --numstat -- $TEST_EXCLUSIONS" 2>/dev/null | \
        awk '{ sum += $1 } END { print sum+0 }'
}

# Check if there are staged changes
# Returns 0 (true) if there ARE staged changes, 1 (false) if none
has_staged_changes() {
    ! git diff --cached --quiet 2>/dev/null
}

# Get added lines - auto-detects context (staged vs branch)
# Returns: number of lines added (production code only)
get_added_lines() {
    # Check if we have staged changes
    local has_staged
    has_staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$has_staged" -gt 0 ]]; then
        # Have staged changes, count those
        get_staged_added_lines
    else
        # No staged changes, compare branch to main
        get_branch_added_lines "main"
    fi
}

# Count total added lines including tests
get_total_added_lines() {
    local has_staged
    has_staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$has_staged" -gt 0 ]]; then
        git diff --cached --numstat 2>/dev/null | \
            awk '{ sum += $1 } END { print sum+0 }'
    else
        git diff main...HEAD --numstat 2>/dev/null | \
            awk '{ sum += $1 } END { print sum+0 }'
    fi
}

# Count test file additions
get_test_added_lines() {
    local total
    local prod
    total=$(get_total_added_lines)
    prod=$(get_added_lines)
    echo $((total - prod))
}

# Check if the current change is "large" (exceeds threshold)
# Returns: 0 (true) if large, 1 (false) if small
is_large_change() {
    local added
    added=$(get_added_lines)
    [[ "$added" -gt "$DIFF_LIMIT" ]]
}

# Output all size info as JSON
get_size_json() {
    local prod_lines test_lines total_lines threshold is_large
    prod_lines=$(get_added_lines)
    test_lines=$(get_test_added_lines)
    total_lines=$(get_total_added_lines)
    threshold=$(get_size_threshold)

    # Determine if large - compare directly to avoid set -e issues
    if [[ "$prod_lines" -gt "$threshold" ]]; then
        is_large="true"
    else
        is_large="false"
    fi

    cat <<EOF
{
  "production_lines": $prod_lines,
  "test_lines": $test_lines,
  "total_lines": $total_lines,
  "threshold": $threshold,
  "is_large": $is_large
}
EOF
}

# CLI interface when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --is-large)
            if is_large_change; then
                exit 0
            else
                exit 1
            fi
            ;;
        --threshold)
            get_size_threshold
            ;;
        --json)
            get_size_json
            ;;
        --help|-h)
            echo "Usage: change-size.sh [OPTION]"
            echo ""
            echo "Calculate change size for commits or branches."
            echo ""
            echo "Options:"
            echo "  (none)       Print lines added (production code)"
            echo "  --is-large   Exit 0 if large change, 1 if small"
            echo "  --threshold  Print the configured size threshold"
            echo "  --json       Output all metrics as JSON"
            echo "  --help       Show this help"
            echo ""
            echo "Environment:"
            echo "  DIFF_LIMIT   Override threshold (default: 150)"
            ;;
        *)
            get_added_lines
            ;;
    esac
fi
