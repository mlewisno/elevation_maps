#!/usr/bin/env bash
#
# config-check.sh - Validate Claude Code configuration consistency
#
# Checks:
# - Valid JSON syntax in settings.json and settings.local.json
# - New executable scripts are registered in permissions.allow
# - Orphaned permissions (allow entries for non-existent files)
# - Validators in config.sh exist as files
#
# Usage: config-check.sh
# Returns: 0 on success, 1 on blocking errors, 2 on warnings only

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
CONFIG_CHECK_ENABLED=true
CONFIG_CHECK_BLOCKING=true

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Counters
ERRORS=()
WARNINGS=()

error() {
    ERRORS+=("$1")
    echo -e "${RED}ERROR:${NC} $1" >&2
}

warn() {
    WARNINGS+=("$1")
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Find project root (where .claude directory is)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.claude" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "$PWD"
}

PROJECT_ROOT=$(find_project_root)

# Validate JSON syntax
check_json_syntax() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 0  # File doesn't exist, not an error
    fi

    if command -v jq &>/dev/null; then
        if ! jq empty "$file" 2>/dev/null; then
            error "$file: Invalid JSON syntax"
            jq empty "$file" 2>&1 | head -5
            return 1
        fi
        success "$file: Valid JSON"
    elif command -v python3 &>/dev/null; then
        if ! python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
            error "$file: Invalid JSON syntax"
            return 1
        fi
        success "$file: Valid JSON"
    else
        warn "Neither jq nor python3 available - skipping JSON validation"
    fi
}

# Check that new scripts are registered in permissions
check_new_scripts() {
    local settings_local="$PROJECT_ROOT/.claude/settings.local.json"

    # Get new executable scripts from staged changes
    local new_scripts
    new_scripts=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | \
        grep -E '^scripts/.*\.sh$' || true)

    if [[ -z "$new_scripts" ]]; then
        return 0
    fi

    if [[ ! -f "$settings_local" ]]; then
        warn "No settings.local.json found - new scripts may need manual permission grants"
        return 0
    fi

    local settings_content
    settings_content=$(cat "$settings_local")

    local unregistered=()

    while IFS= read -r script; do
        # Check if script path appears in settings.local.json
        local script_pattern
        script_pattern=$(echo "$script" | sed 's/\//\\\//g')

        if ! echo "$settings_content" | grep -q "$script_pattern"; then
            unregistered+=("$script")
        fi
    done <<< "$new_scripts"

    if [[ ${#unregistered[@]} -gt 0 ]]; then
        warn "New scripts not registered in settings.local.json:"
        for script in "${unregistered[@]}"; do
            echo "    - $script"
            echo "      Add: \"Bash(./$script:*)\""
        done
        echo ""
        echo "  Without registration, Claude will prompt for permission each time."
        echo "  Add to .claude/settings.local.json permissions.allow array."
    fi
}

# Check for orphaned permissions
check_orphaned_permissions() {
    local settings_local="$PROJECT_ROOT/.claude/settings.local.json"

    if [[ ! -f "$settings_local" ]]; then
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        info "jq not available - skipping orphaned permissions check"
        return 0
    fi

    # Extract Bash permissions that reference local scripts
    local bash_permissions
    bash_permissions=$(jq -r '.permissions.allow[]? // empty' "$settings_local" 2>/dev/null | \
        grep -E '^Bash\(\./scripts/' || true)

    if [[ -z "$bash_permissions" ]]; then
        return 0
    fi

    local orphaned=()

    while IFS= read -r perm; do
        # Extract script path from permission like "Bash(./scripts/hooks/foo.sh:*)"
        local script_path
        script_path=$(echo "$perm" | sed -E 's/^Bash\(\.\/([^:]+):.*/\1/')

        if [[ ! -f "$PROJECT_ROOT/$script_path" ]]; then
            orphaned+=("$perm → $script_path")
        fi
    done <<< "$bash_permissions"

    if [[ ${#orphaned[@]} -gt 0 ]]; then
        warn "Orphaned permissions (scripts don't exist):"
        for entry in "${orphaned[@]}"; do
            echo "    - $entry"
        done
        echo ""
        echo "  Consider removing these from settings.local.json"
    fi
}

# Check validators in config.sh exist
check_validators_exist() {
    local hooks_config="$PROJECT_ROOT/scripts/hooks/config.sh"

    if [[ ! -f "$hooks_config" ]]; then
        return 0
    fi

    # Source the config to get VALIDATORS array
    local validators_line
    validators_line=$(grep -E '^VALIDATORS=' "$hooks_config" || true)

    if [[ -z "$validators_line" ]]; then
        return 0
    fi

    # Parse validators from the line
    # Format: VALIDATORS=(diff-size-check single-concern-check)
    local validators
    validators=$(echo "$validators_line" | sed -E 's/^VALIDATORS=\(([^)]+)\)/\1/')

    local missing=()

    for validator in $validators; do
        local validator_path="$PROJECT_ROOT/scripts/hooks/validators/${validator}.sh"
        if [[ ! -f "$validator_path" ]]; then
            missing+=("$validator")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Validators in config.sh don't exist:"
        for v in "${missing[@]}"; do
            echo "    - $v → scripts/hooks/validators/${v}.sh"
        done
        echo ""
        echo "  Either create the validator or remove from VALIDATORS array"
    else
        success "All configured validators exist"
    fi
}

# Check for new validators not added to config
check_new_validators() {
    local hooks_config="$PROJECT_ROOT/scripts/hooks/config.sh"

    if [[ ! -f "$hooks_config" ]]; then
        return 0
    fi

    # Get new validator files from staged changes
    local new_validators
    new_validators=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | \
        grep -E '^scripts/hooks/validators/[^/]+\.sh$' || true)

    if [[ -z "$new_validators" ]]; then
        return 0
    fi

    # Get current VALIDATORS from config
    local config_content
    config_content=$(cat "$hooks_config")

    local not_in_config=()

    while IFS= read -r validator_file; do
        local validator_name
        validator_name=$(basename "$validator_file" .sh)

        # Skip sub-validators (those in subdirectories)
        if [[ "$validator_file" =~ validators/[^/]+/[^/]+\.sh ]]; then
            continue
        fi

        if ! echo "$config_content" | grep -qE "VALIDATORS=.*$validator_name"; then
            not_in_config+=("$validator_name")
        fi
    done <<< "$new_validators"

    if [[ ${#not_in_config[@]} -gt 0 ]]; then
        info "New validators not added to VALIDATORS array:"
        for v in "${not_in_config[@]}"; do
            echo "    - $v"
        done
        echo ""
        echo "  To enable, add to VALIDATORS in scripts/hooks/config.sh"
        echo "  Example: VALIDATORS=(diff-size-check $v)"
    fi
}

# Main logic
main() {
    if [[ "$CONFIG_CHECK_ENABLED" != "true" ]]; then
        info "Config check is disabled"
        return 0
    fi

    echo ""
    echo "Configuration consistency check:"
    echo ""

    # Check JSON files
    check_json_syntax "$PROJECT_ROOT/.claude/settings.json"
    check_json_syntax "$PROJECT_ROOT/.claude/settings.local.json"
    echo ""

    # Check script registration
    check_new_scripts
    check_orphaned_permissions
    echo ""

    # Check validator consistency
    check_validators_exist
    check_new_validators
    echo ""

    # Summary
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}Found ${#ERRORS[@]} error(s)${NC}"
        if [[ "$CONFIG_CHECK_BLOCKING" == "true" ]]; then
            return 1
        fi
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Found ${#WARNINGS[@]} warning(s)${NC}"
        if [[ ${#ERRORS[@]} -eq 0 ]]; then
            return 2  # Warnings only
        fi
    fi

    if [[ ${#ERRORS[@]} -eq 0 ]] && [[ ${#WARNINGS[@]} -eq 0 ]]; then
        success "All configuration checks passed"
    fi

    return 0
}

main "$@"
