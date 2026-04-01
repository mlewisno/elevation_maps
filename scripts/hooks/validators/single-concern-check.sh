#!/usr/bin/env bash
#
# single-concern-check.sh - Heuristic warnings for multi-concern commits
#
# This script provides WARNINGS only - it never blocks commits.
# Use [multi] tag to acknowledge and suppress warnings.
#
# Heuristics:
# - File count: >5 files triggers warning
# - Directory spread: >2 top-level dirs triggers warning
# - Commit message contains "and" triggers warning
#
# Usage: single-concern-check.sh [commit-msg-file]
# Returns: Always 0 (warnings only, never blocks)

set -euo pipefail

# Colors for output
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Thresholds
FILE_COUNT_THRESHOLD=5
DIR_SPREAD_THRESHOLD=2

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Check for [multi] override via environment variable, commit message, or git log
has_multi_override() {
    local commit_msg_file="${1:-}"

    # Check environment variable (works in any hook context, including pre-commit)
    if [[ "${ALLOW_MULTI:-}" == "1" ]]; then
        return 0
    fi

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if head -1 "$commit_msg_file" | grep -qE '\[multi\]'; then
            return 0
        fi
    fi

    # Also check the last commit subject if we're in pre-push
    if git log -1 --pretty=%s 2>/dev/null | grep -qE '\[multi\]'; then
        return 0
    fi

    return 1
}

# Count staged files
count_staged_files() {
    git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' '
}

# Get top-level directories of staged files
get_top_level_dirs() {
    git diff --cached --name-only 2>/dev/null | \
        cut -d'/' -f1 | \
        sort -u
}

# Count unique top-level directories
count_top_level_dirs() {
    get_top_level_dirs | wc -l | tr -d ' '
}

# Check if commit message contains "and" (simple heuristic)
message_contains_and() {
    local commit_msg_file="${1:-}"
    local subject=""

    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        subject=$(head -n1 "$commit_msg_file")
    else
        subject=$(git log -1 --pretty=%s 2>/dev/null || echo "")
    fi

    # Look for " and " in the subject (space-bounded to avoid false positives)
    # Exclude common patterns that aren't multi-concern indicators
    if echo "$subject" | grep -qE ' and ' | grep -vE '(search and replace|cut and paste|copy and paste)'; then
        return 0
    fi

    return 1
}

# Main logic
main() {
    local commit_msg_file="${1:-}"
    local warnings=0

    # Check for override first
    if has_multi_override "$commit_msg_file"; then
        info "Found [multi] tag - skipping single-concern checks"
        return 0
    fi

    echo ""
    echo "Single-concern analysis:"

    # Check 1: File count
    local file_count
    file_count=$(count_staged_files)

    if [[ "$file_count" -gt "$FILE_COUNT_THRESHOLD" ]]; then
        warn "Commit touches $file_count files (threshold: $FILE_COUNT_THRESHOLD)"
        echo "  Consider: Does this commit do one thing?"
        warnings=$((warnings + 1))
    else
        echo "  Files changed: $file_count (OK)"
    fi

    # Check 2: Directory spread
    local dir_count
    dir_count=$(count_top_level_dirs)

    if [[ "$dir_count" -gt "$DIR_SPREAD_THRESHOLD" ]]; then
        warn "Changes span $dir_count top-level directories"
        echo "  Directories: $(get_top_level_dirs | tr '\n' ' ')"
        echo "  Consider: Are these changes related?"
        warnings=$((warnings + 1))
    else
        echo "  Directory spread: $dir_count dirs (OK)"
    fi

    # Check 3: "and" in commit message
    if message_contains_and "$commit_msg_file"; then
        local subject=""
        if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
            subject=$(head -n1 "$commit_msg_file")
        fi
        warn "Commit message contains 'and' - may indicate multiple concerns"
        echo "  Message: $subject"
        echo "  Consider: Can this be split into separate commits?"
        warnings=$((warnings + 1))
    fi

    echo ""

    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}Found $warnings potential concern(s).${NC}"
        echo ""
        echo "These are warnings only - commit will proceed."
        echo "To suppress: ALLOW_MULTI=1 git commit -m 'type(scope): description [multi]'"
    else
        success "Commit appears focused on a single concern"
    fi

    # Always return 0 - this is advisory only
    return 0
}

main "$@"
