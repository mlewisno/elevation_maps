#!/usr/bin/env bash
#
# adr-lint.sh - Validate ADR structure and content
#
# Checks:
# - Required sections present (Context, Decision, Consequences)
# - Metadata table has required fields (ID, Type, Status)
# - Status is valid (Proposed, Accepted, Deprecated, Superseded)
# - Type is valid (architecture, technology, process, product)
# - Filename matches ADR-XXX pattern
# - Alternatives section is not empty (warning)
#
# Usage: adr-lint.sh [file|directory]
# Returns: 0 on success, 1 on errors, 2 on warnings only

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Valid values
VALID_STATUSES="Proposed|Accepted|Deprecated|Superseded"
VALID_TYPES="architecture|technology|process|product"

# Required sections (case-insensitive)
REQUIRED_SECTIONS=(
    "Context"
    "Decision"
    "Consequences"
)

# Recommended sections (warnings if missing)
RECOMMENDED_SECTIONS=(
    "Alternatives"
)

# Validate a single ADR file
validate_adr() {
    local file="$1"
    local filename
    local errors=0
    local warnings=0

    filename=$(basename "$file")

    # Check filename format
    if ! echo "$filename" | grep -qE '^ADR-[0-9]{3}-.*\.md$'; then
        error "$filename: Invalid filename format (expected ADR-XXX-title.md)"
        ((errors++))
    fi

    # Read file content
    local content
    content=$(cat "$file")

    # Check for metadata table
    if ! echo "$content" | grep -qE '^\| Field \| Value \|'; then
        error "$filename: Missing metadata table"
        ((errors++))
    else
        # Check ID field
        if ! echo "$content" | grep -qE '^\| ID \| ADR-[0-9]+'; then
            error "$filename: Missing or invalid ID in metadata"
            ((errors++))
        fi

        # Check Type field
        local adr_type
        adr_type=$(echo "$content" | grep -E '^\| Type \|' | sed 's/.*| \(.*\) |$/\1/' | tr -d ' ')
        if [[ -z "$adr_type" ]]; then
            error "$filename: Missing Type in metadata"
            ((errors++))
        elif ! echo "$adr_type" | grep -qiE "^($VALID_TYPES)$"; then
            error "$filename: Invalid Type '$adr_type' (expected: architecture, technology, process, or product)"
            ((errors++))
        fi

        # Check Status field
        local status
        status=$(echo "$content" | grep -E '^\| Status \|' | sed 's/.*| \(.*\) |$/\1/' | tr -d ' ')
        if [[ -z "$status" ]]; then
            error "$filename: Missing Status in metadata"
            ((errors++))
        elif ! echo "$status" | grep -qiE "^($VALID_STATUSES)$"; then
            error "$filename: Invalid Status '$status' (expected: Proposed, Accepted, Deprecated, or Superseded)"
            ((errors++))
        fi

        # Check Created field
        if ! echo "$content" | grep -qE '^\| Created \| [0-9]{4}-[0-9]{2}-[0-9]{2}'; then
            warn "$filename: Missing or invalid Created date (expected YYYY-MM-DD)"
            ((warnings++))
        fi
    fi

    # Check required sections
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! echo "$content" | grep -qiE "^## $section"; then
            error "$filename: Missing required section '## $section'"
            ((errors++))
        fi
    done

    # Check recommended sections
    for section in "${RECOMMENDED_SECTIONS[@]}"; do
        if ! echo "$content" | grep -qiE "^## $section"; then
            warn "$filename: Missing recommended section '## $section'"
            ((warnings++))
        fi
    done

    # Check for empty Context section
    local context_content
    context_content=$(echo "$content" | sed -n '/^## Context/,/^## /p' | grep -v '^## ' | tr -d '[:space:]')
    if [[ -z "$context_content" ]] || [[ "$context_content" == *"[What is the issue"* ]]; then
        warn "$filename: Context section appears to be empty or contains placeholder text"
        ((warnings++))
    fi

    # Check for empty Decision section
    local decision_content
    decision_content=$(echo "$content" | sed -n '/^## Decision/,/^## /p' | grep -v '^## ' | tr -d '[:space:]')
    if [[ -z "$decision_content" ]] || [[ "$decision_content" == *"[What is the change"* ]]; then
        warn "$filename: Decision section appears to be empty or contains placeholder text"
        ((warnings++))
    fi

    # Return status
    if [[ $errors -gt 0 ]]; then
        return 1
    elif [[ $warnings -gt 0 ]]; then
        return 2
    else
        return 0
    fi
}

# Run markdownlint if available
run_markdownlint() {
    local file="$1"
    local config_file="${2:-.specs/.markdownlint.yml}"

    if command -v markdownlint &> /dev/null; then
        if [[ -f "$config_file" ]]; then
            markdownlint -c "$config_file" "$file" 2>&1 || true
        else
            markdownlint "$file" 2>&1 || true
        fi
    elif command -v npx &> /dev/null; then
        if [[ -f "$config_file" ]]; then
            npx markdownlint-cli -c "$config_file" "$file" 2>&1 || true
        else
            npx markdownlint-cli "$file" 2>&1 || true
        fi
    fi
}

# Main logic
main() {
    local target="${1:-.specs/ADRs}"
    local total_errors=0
    local total_warnings=0
    local files_checked=0

    # Find ADR files
    local files=()
    if [[ -f "$target" ]]; then
        files=("$target")
    elif [[ -d "$target" ]]; then
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$target" -name "ADR-*.md" -print0 2>/dev/null)
    else
        error "Target not found: $target"
        exit 1
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        info "No ADR files found in $target"
        exit 0
    fi

    echo ""
    echo "Validating ${#files[@]} ADR file(s)..."
    echo ""

    for file in "${files[@]}"; do
        info "Checking $(basename "$file")..."

        # Run structure validation
        set +e
        validate_adr "$file"
        local result=$?
        set -e

        if [[ $result -eq 1 ]]; then
            ((total_errors++))
        elif [[ $result -eq 2 ]]; then
            ((total_warnings++))
        fi

        # Run markdownlint
        local lint_output
        lint_output=$(run_markdownlint "$file")
        if [[ -n "$lint_output" ]]; then
            echo "$lint_output"
        fi

        ((files_checked++))
    done

    echo ""
    echo "---"
    echo "ADR Lint Summary: $files_checked file(s) checked"

    if [[ $total_errors -gt 0 ]]; then
        error "$total_errors file(s) with errors"
        exit 1
    elif [[ $total_warnings -gt 0 ]]; then
        warn "$total_warnings file(s) with warnings"
        exit 0
    else
        success "All ADRs passed validation"
        exit 0
    fi
}

main "$@"
