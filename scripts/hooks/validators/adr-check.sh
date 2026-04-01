#!/usr/bin/env bash
#
# adr-check.sh - Advisory check for undocumented architectural decisions
#
# Rules (all warnings, never blocks):
# - Detects dependency file changes (Gemfile, package.json, go.mod, etc.)
# - Detects decision language in commit messages
# - Suggests /decision or [no-adr] override tag
#
# Usage: adr-check.sh [commit-msg-file]
# Returns: Always 0 (advisory only)

set -euo pipefail

# Colors for output
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Default values
ADR_CHECK_ENABLED=true

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Exit early if disabled
if [[ "$ADR_CHECK_ENABLED" != "true" ]]; then
    exit 0
fi

warn() {
    echo -e "${YELLOW}ADR NOTICE:${NC} $1" >&2
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Check for [no-adr] override in commit subject line
has_no_adr_override() {
    local commit_msg_file="${1:-}"

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if head -1 "$commit_msg_file" | grep -qE '\[no-adr\]'; then
            return 0
        fi
    fi

    # Also check the last commit subject if we're in pre-push
    if git log -1 --pretty=%s 2>/dev/null | grep -qE '\[no-adr\]'; then
        return 0
    fi

    return 1
}

# Check for ADR reference in commit message
has_adr_reference() {
    local commit_msg_file="${1:-}"

    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if grep -qiE '(ADR-[0-9]+|Implements ADR)' "$commit_msg_file"; then
            return 0
        fi
    fi

    # Also check the last commit if we're in pre-push
    if git log -1 --pretty=%B 2>/dev/null | grep -qiE '(ADR-[0-9]+|Implements ADR)'; then
        return 0
    fi

    return 1
}

# Dependency file patterns
DEPENDENCY_FILES=(
    "Gemfile"
    "Gemfile.lock"
    "package.json"
    "package-lock.json"
    "yarn.lock"
    "pnpm-lock.yaml"
    "go.mod"
    "go.sum"
    "Cargo.toml"
    "Cargo.lock"
    "requirements.txt"
    "Pipfile"
    "Pipfile.lock"
    "pyproject.toml"
    "poetry.lock"
    "composer.json"
    "composer.lock"
    "build.gradle"
    "pom.xml"
)

# Decision language patterns in commit messages
DECISION_PATTERNS=(
    "instead of"
    "migrate to"
    "switch to"
    "replace.*with"
    "chose"
    "decided"
    "moving to"
    "adopting"
    "deprecating"
    "dropping support"
)

# Check if any dependency files are staged
check_dependency_changes() {
    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null || true)

    local found_deps=()
    for dep_file in "${DEPENDENCY_FILES[@]}"; do
        if echo "$staged_files" | grep -qE "(^|/)${dep_file}$"; then
            found_deps+=("$dep_file")
        fi
    done

    if [[ ${#found_deps[@]} -gt 0 ]]; then
        echo "${found_deps[*]}"
        return 0
    fi
    return 1
}

# Check commit message for decision language
check_decision_language() {
    local commit_msg_file="${1:-}"
    local commit_msg=""

    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        commit_msg=$(cat "$commit_msg_file")
    else
        commit_msg=$(git log -1 --pretty=%B 2>/dev/null || true)
    fi

    local found_patterns=()
    for pattern in "${DECISION_PATTERNS[@]}"; do
        if echo "$commit_msg" | grep -qiE "$pattern"; then
            found_patterns+=("$pattern")
        fi
    done

    if [[ ${#found_patterns[@]} -gt 0 ]]; then
        echo "${found_patterns[*]}"
        return 0
    fi
    return 1
}

# Main logic
main() {
    local commit_msg_file="${1:-}"
    local warnings=()

    # Check for override first
    if has_no_adr_override "$commit_msg_file"; then
        info "Found [no-adr] tag - skipping ADR check"
        exit 0
    fi

    # Skip if already references an ADR
    if has_adr_reference "$commit_msg_file"; then
        exit 0
    fi

    # Check for dependency changes
    local dep_changes
    if dep_changes=$(check_dependency_changes); then
        warnings+=("Dependency files changed: $dep_changes")
    fi

    # Check for decision language
    local decision_lang
    if decision_lang=$(check_decision_language "$commit_msg_file"); then
        warnings+=("Decision language detected: $decision_lang")
    fi

    # If we found anything, print advisory notice
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        warn "Potential undocumented decision detected"
        echo ""
        for warning in "${warnings[@]}"; do
            echo "  - $warning"
        done
        echo ""
        echo "Consider documenting this decision:"
        echo "  Run: /decision \"Brief description\""
        echo ""
        echo "To suppress this notice:"
        echo "  - Add [no-adr] to commit subject"
        echo "  - Or reference existing ADR: \"Implements ADR-XXX\""
        echo ""
    fi

    # Always return 0 - this is advisory only
    exit 0
}

main "$@"
