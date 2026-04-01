#!/usr/bin/env bash
#
# diff-size-check.sh - Enforce diff size limits
#
# Rules:
# - Max 150 lines added per commit (production code only)
# - Test files excluded (spec/, test/, *_test.go, *_spec.rb, *.test.ts, etc.)
# - Unlimited removals (cleanup commits allowed)
# - Override with [large] tag in commit message
#
# Usage: diff-size-check.sh [commit-msg-file]
# Returns: 0 on success, 1 on error

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Load shared change-size library
LIB_DIR="${SCRIPT_DIR}/../lib"
if [[ -f "${LIB_DIR}/change-size.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/change-size.sh"
fi

# Default values (may be overridden by config.sh or change-size.sh)
DIFF_LIMIT="${DIFF_LIMIT:-150}"
ALLOW_LARGE_OVERRIDE=true

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Check for [large] override via environment variable, commit message, or git log
has_large_override() {
    local commit_msg_file="${1:-}"

    # Check environment variable (works in any hook context, including pre-commit)
    if [[ "${ALLOW_LARGE:-}" == "1" ]]; then
        return 0
    fi

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if head -1 "$commit_msg_file" | grep -qE '\[large\]'; then
            return 0
        fi
    fi

    # Also check the last commit subject if we're in pre-push
    if git log -1 --pretty=%s 2>/dev/null | grep -qE '\[large\]'; then
        return 0
    fi

    return 1
}

# Use shared library functions if available, otherwise define locally
if ! declare -f get_staged_added_lines >/dev/null 2>&1; then
    # Fallback: define functions locally if library not loaded
    # Test file patterns to exclude (using :(exclude) for compatibility)
    TEST_EXCLUSIONS="':(exclude)spec/' ':(exclude)test/' ':(exclude)tests/' ':(exclude)**/__tests__/' ':(exclude)*_test.go' ':(exclude)*_spec.rb' ':(exclude)*.test.ts' ':(exclude)*.test.tsx' ':(exclude)*.test.js' ':(exclude)*.test.jsx' ':(exclude)*.spec.ts' ':(exclude)*.spec.tsx' ':(exclude)*.spec.js' ':(exclude)*.spec.jsx' ':(exclude)*_test.py' ':(exclude)test_*.py' ':(exclude)*Test.java' ':(exclude)*_test.rs'"

    get_staged_added_lines() {
        eval "git diff --cached --numstat -- $TEST_EXCLUSIONS" 2>/dev/null | \
            awk '{ sum += $1 } END { print sum+0 }'
    }

    get_total_added_lines() {
        git diff --cached --numstat 2>/dev/null | \
            awk '{ sum += $1 } END { print sum+0 }'
    }

    get_test_added_lines() {
        local total prod
        total=$(get_total_added_lines)
        prod=$(get_staged_added_lines)
        echo $((total - prod))
    }
fi

# Wrapper for backward compatibility
count_added_lines() {
    get_staged_added_lines
}

count_total_added_lines() {
    get_total_added_lines
}

count_test_lines() {
    get_test_added_lines
}

# Main logic
main() {
    local commit_msg_file="${1:-}"

    # Check for override first
    if [[ "$ALLOW_LARGE_OVERRIDE" == "true" ]] && has_large_override "$commit_msg_file"; then
        info "Found [large] tag - skipping diff size check"
        return 0
    fi

    local added_lines
    local total_lines
    local test_lines

    added_lines=$(count_added_lines)
    total_lines=$(count_total_added_lines)
    test_lines=$(count_test_lines)

    echo ""
    echo "Diff size analysis:"
    echo "  Production code: +$added_lines lines"
    echo "  Test code:       +$test_lines lines"
    echo "  Total:           +$total_lines lines"
    echo ""

    if [[ "$added_lines" -gt "$DIFF_LIMIT" ]]; then
        error "Commit adds $added_lines lines of production code (limit: $DIFF_LIMIT)"
        echo ""
        echo "Options:"
        echo "  1. Split this commit into smaller, focused changes"
        echo "  2. If this large commit is intentional, use ALLOW_LARGE with [large] tag:"
        echo "     ALLOW_LARGE=1 git commit -m 'feat(import): add bulk import [large]'"
        echo ""
        echo "Staged files:"
        git diff --cached --stat | head -20
        return 1
    fi

    if [[ "$added_lines" -gt $((DIFF_LIMIT * 3 / 4)) ]]; then
        warn "Commit is approaching the $DIFF_LIMIT line limit ($added_lines lines)"
        echo "  Consider if this can be split into smaller commits."
    fi

    success "Diff size is within limits ($added_lines/$DIFF_LIMIT lines)"
    return 0
}

main "$@"
