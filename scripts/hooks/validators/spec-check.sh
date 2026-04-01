#!/usr/bin/env bash
#
# spec-check.sh - Validate feature commits have linked specs
#
# Rules:
# - Commits with "feat(" type should reference a spec or issue
# - Warns if spec status is "Draft" (not blocking)
# - Override with [no-spec] tag in commit message
#
# Usage: spec-check.sh [commit-msg-file]
# Returns: 0 on success (or warning), 1 on error

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

# Default values
SPEC_CHECK_ENABLED=true
SPEC_REQUIRE_ISSUE_REF=false
SPEC_WARN_ON_DRAFT=true

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

# Check for [no-spec] override in commit subject line
has_nospec_override() {
    local commit_msg_file="${1:-}"

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if head -1 "$commit_msg_file" | grep -qE '\[no-spec\]'; then
            return 0
        fi
    fi

    # Also check the last commit subject if we're in pre-push
    if git log -1 --pretty=%s 2>/dev/null | grep -qE '\[no-spec\]'; then
        return 0
    fi

    return 1
}

# Check if commit is a feature commit
is_feature_commit() {
    local commit_msg_file="${1:-}"
    local subject=""

    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        subject=$(head -1 "$commit_msg_file")
    else
        subject=$(git log -1 --pretty=%s 2>/dev/null || echo "")
    fi

    # Check for feat( prefix
    if echo "$subject" | grep -qE '^feat\('; then
        return 0
    fi

    return 1
}

# Extract issue reference from commit message
get_issue_ref() {
    local commit_msg_file="${1:-}"
    local message=""

    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        message=$(cat "$commit_msg_file")
    else
        message=$(git log -1 --pretty=%B 2>/dev/null || echo "")
    fi

    # Look for patterns like #123, Refs #123, Closes #123, FEAT-001
    local ref=""

    # GitHub issue references
    ref=$(echo "$message" | grep -oE '#[0-9]+' | head -1 || echo "")
    if [[ -n "$ref" ]]; then
        echo "$ref"
        return 0
    fi

    # FEAT-XXX references
    ref=$(echo "$message" | grep -oE 'FEAT-[0-9]+' | head -1 || echo "")
    if [[ -n "$ref" ]]; then
        echo "$ref"
        return 0
    fi

    echo ""
    return 1
}

# Check if spec exists for a FEAT reference
check_spec_exists() {
    local feat_ref="$1"
    local spec_file

    # Try to find matching spec file
    spec_file=$(find .specs/features -name "${feat_ref}*.md" 2>/dev/null | head -1 || echo "")

    if [[ -n "$spec_file" ]] && [[ -f "$spec_file" ]]; then
        echo "$spec_file"
        return 0
    fi

    return 1
}

# Get spec status from spec file
get_spec_status() {
    local spec_file="$1"

    if [[ -f "$spec_file" ]]; then
        # Look for Status field in metadata table
        grep -E '\| Status \|' "$spec_file" | sed 's/.*| Status |[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | head -1 || echo "Unknown"
    else
        echo "Not Found"
    fi
}

# Main logic
main() {
    local commit_msg_file="${1:-}"

    # Skip if spec checking is disabled
    if [[ "$SPEC_CHECK_ENABLED" != "true" ]]; then
        info "Spec checking disabled"
        return 0
    fi

    # Check for override first
    if has_nospec_override "$commit_msg_file"; then
        info "Found [no-spec] tag - skipping spec check"
        return 0
    fi

    # Only check feature commits
    if ! is_feature_commit "$commit_msg_file"; then
        # Not a feature commit, skip check
        return 0
    fi

    echo ""
    echo "Feature commit detected - checking spec linkage..."

    # Get any issue/spec reference
    local ref
    ref=$(get_issue_ref "$commit_msg_file" || echo "")

    if [[ -z "$ref" ]]; then
        if [[ "$SPEC_REQUIRE_ISSUE_REF" == "true" ]]; then
            error "Feature commit must reference an issue or spec"
            echo ""
            echo "Add a reference in your commit message:"
            echo "  - GitHub issue: Refs #123"
            echo "  - Feature spec: FEAT-001"
            echo ""
            echo "Or add [no-spec] to skip this check for trivial features:"
            echo "  feat(ui): add hover effect [no-spec]"
            return 1
        else
            warn "Feature commit has no issue/spec reference"
            echo ""
            echo "Consider linking to a spec for better traceability:"
            echo "  - Run /feature-spec to create a spec"
            echo "  - Add 'Refs #123' or 'FEAT-001' to commit message"
            return 0
        fi
    fi

    # If it's a FEAT reference, check the spec exists
    if echo "$ref" | grep -qE '^FEAT-'; then
        local spec_file
        if spec_file=$(check_spec_exists "$ref"); then
            local status
            status=$(get_spec_status "$spec_file")

            if [[ "$SPEC_WARN_ON_DRAFT" == "true" ]] && [[ "$status" == "Draft" ]]; then
                warn "Spec $ref is still in Draft status"
                echo "  File: $spec_file"
                echo "  Consider marking as 'Ready' before implementing"
            else
                success "Found spec: $spec_file (Status: $status)"
            fi
        else
            warn "Referenced spec $ref not found"
            echo "  Expected: .specs/features/${ref}.md"
            echo "  Run /feature-spec to create it"
        fi
    else
        # GitHub issue reference
        info "Commit references $ref"
        echo "  Consider creating a spec with /feature-spec"
    fi

    return 0
}

main "$@"
