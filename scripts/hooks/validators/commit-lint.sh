#!/usr/bin/env bash
#
# commit-lint.sh - Validate commit message format
#
# Checks:
# 1. Subject matches conventional commit format: <type>(<scope>): <description>
# 2. Subject line under 72 characters
# 3. "Why:" section present for non-trivial commits
# 4. Warning if "Changes:" section missing
#
# Usage: commit-lint.sh <commit-msg-file>
# Returns: 0 on success, 1 on error

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Valid commit types
VALID_TYPES="feat|fix|refactor|docs|test|chore|style|perf"

# Trivial commit patterns (don't require Why section)
TRIVIAL_PATTERNS=(
    "^docs\(.*\): fix typo"
    "^chore\(deps\):"
    "^style\(.*\):"
)

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

# Check if commit message file was provided
if [[ $# -lt 1 ]]; then
    error "Usage: commit-lint.sh <commit-msg-file>"
    exit 1
fi

COMMIT_MSG_FILE="$1"

if [[ ! -f "$COMMIT_MSG_FILE" ]]; then
    error "Commit message file not found: $COMMIT_MSG_FILE"
    exit 1
fi

# Read commit message
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")
SUBJECT=$(echo "$COMMIT_MSG" | head -n1)
BODY=$(echo "$COMMIT_MSG" | tail -n +3)

ERRORS=0
WARNINGS=0

# Check 1: Subject matches conventional commit format
if ! echo "$SUBJECT" | grep -qE "^($VALID_TYPES)\([a-z0-9-]+\): .+"; then
    error "Subject must match format: <type>(<scope>): <description>"
    echo "  Valid types: feat, fix, refactor, docs, test, chore, style, perf"
    echo "  Example: feat(auth): add password reset flow"
    echo "  Got: $SUBJECT"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Subject line length
SUBJECT_LENGTH=${#SUBJECT}
if [[ $SUBJECT_LENGTH -gt 72 ]]; then
    error "Subject line too long: $SUBJECT_LENGTH characters (max 72)"
    ERRORS=$((ERRORS + 1))
elif [[ $SUBJECT_LENGTH -gt 60 ]]; then
    warn "Subject line is getting long: $SUBJECT_LENGTH characters (aim for <60)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 3: Determine if commit is trivial
is_trivial() {
    for pattern in "${TRIVIAL_PATTERNS[@]}"; do
        if echo "$SUBJECT" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Check for Why section (required for non-trivial commits)
if ! is_trivial; then
    if ! echo "$BODY" | grep -qE "^Why:"; then
        warn "Missing 'Why:' section. Explain the motivation for this change."
        echo "  Add a line starting with 'Why:' after the subject."
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Check 4: Warn if Changes section missing (for commits with body)
if [[ -n "$BODY" ]] && ! echo "$BODY" | grep -qE "^Changes:"; then
    # Only warn for commits that have a body but no Changes section
    if echo "$BODY" | grep -qE "^Why:"; then
        warn "Consider adding a 'Changes:' section listing files and what changed."
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Check 5: Subject should not end with period
if echo "$SUBJECT" | grep -qE '\.$'; then
    warn "Subject line should not end with a period."
    WARNINGS=$((WARNINGS + 1))
fi

# Check 6: Use imperative mood hint (starts with lowercase after colon)
# This is just a hint, not enforced
DESC=$(echo "$SUBJECT" | sed -E 's/^[^:]+: //')
FIRST_CHAR=$(echo "$DESC" | cut -c1)
if [[ "$FIRST_CHAR" =~ [A-Z] ]]; then
    # Uppercase is fine, just checking it's not past tense
    if echo "$DESC" | grep -qE "^(Added|Fixed|Updated|Changed|Removed|Implemented)"; then
        warn "Use imperative mood: 'add' not 'Added', 'fix' not 'Fixed'"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Summary
echo ""
if [[ $ERRORS -gt 0 ]]; then
    error "Commit message validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    warn "Commit message has $WARNINGS warning(s)"
    success "Proceeding with warnings"
    exit 0
else
    success "Commit message format is valid"
    exit 0
fi
