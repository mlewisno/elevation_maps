#!/usr/bin/env bash
#
# twelve-factor-check.sh - 12-Factor App compliance validation
#
# Checks for compliance with automatable 12-factor principles:
# - Factor 2: Dependencies (lockfile presence)
# - Factor 3: Config (no hardcoded secrets/config)
# - Factor 10: Dev/Prod Parity (no env-specific branching)
# - Factor 11: Logs (stdout, not file-based)
#
# Usage: twelve-factor-check.sh [commit-msg-file]
# Returns: 0 on success, 1 on blocking failure
#
# Override tags (in commit subject):
#   [no-lockfile]     - Skip dependency check
#   [no-secret-check] - Skip secret detection
#   [env-branch]      - Acknowledge environment branching
#   [file-logs]       - Acknowledge file-based logging

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Defaults - all checks enabled, most advisory
TWELVE_FACTOR_ENABLED=true
TF_DEPENDENCIES_ENABLED=true
TF_CONFIG_ENABLED=true
TF_LOGS_ENABLED=true
TF_PARITY_ENABLED=true

# Blocking behavior
TF_SECRETS_BLOCKING=true
TF_LOCKFILE_BLOCKING=true
TF_CONFIG_BLOCKING=false
TF_LOGS_BLOCKING=false
TF_PARITY_BLOCKING=false

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Counters for summary
ERRORS=0
WARNINGS=0

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
    WARNINGS=$((WARNINGS + 1))
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

header() {
    echo -e "${BOLD}$1${NC}"
}

# Get commit subject line for override tag checking
get_commit_subject() {
    local commit_msg_file="${1:-}"

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        head -1 "$commit_msg_file"
        return
    fi

    # Fall back to last commit subject if we're in pre-push
    git log -1 --pretty=%s 2>/dev/null || echo ""
}

# Check for specific override tag in commit subject
has_override() {
    local tag="$1"
    local subject="$2"

    echo "$subject" | grep -qE "\[$tag\]"
}

# Detect project type based on manifest files
detect_project_type() {
    local types=()

    if [[ -f "Gemfile" ]]; then
        types+=("ruby")
    fi

    if [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]] || [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
        types+=("python")
    fi

    if [[ -f "go.mod" ]]; then
        types+=("go")
    fi

    if [[ -f "package.json" ]]; then
        types+=("node")
    fi

    if [[ ${#types[@]} -eq 0 ]]; then
        echo "unknown"
    else
        echo "${types[*]}"
    fi
}

# Run a sub-check script
# Prefers Ruby validators when available, falls back to bash
run_check() {
    local check_name="$1"
    local commit_msg_file="${2:-}"
    local ruby_validator="${SCRIPT_DIR}/../../validators/bin/${check_name}"
    local bash_script="${SCRIPT_DIR}/twelve-factor/${check_name}.sh"

    # Prefer Ruby validator if available (secret-detector for config)
    if [[ "$check_name" == "config" ]]; then
        ruby_validator="${SCRIPT_DIR}/../../validators/bin/secret-detector"
        if [[ -x "$ruby_validator" ]] && command -v ruby &>/dev/null; then
            local -a ruby_args
            ruby_args=()
            [[ "$TF_SECRETS_BLOCKING" != "true" ]] && ruby_args+=("--no-block")
            [[ "$TF_CONFIG_BLOCKING" == "true" ]] && ruby_args+=("--config-blocking")
            if [[ ${#ruby_args[@]} -eq 0 ]]; then
                "$ruby_validator"
            else
                "$ruby_validator" "${ruby_args[@]}"
            fi
            return $?
        fi
    fi

    # Fall back to bash script
    if [[ ! -x "$bash_script" ]]; then
        warn "Sub-check not found or not executable: $bash_script"
        return 0
    fi

    "$bash_script" "$commit_msg_file"
}

# Main
main() {
    local commit_msg_file="${1:-}"
    local subject
    local project_types
    local check_result=0
    local failed=0

    # Skip if disabled
    if [[ "$TWELVE_FACTOR_ENABLED" != "true" ]]; then
        return 0
    fi

    subject=$(get_commit_subject "$commit_msg_file")
    project_types=$(detect_project_type)

    echo ""
    header "12-Factor Compliance Check"
    echo ""

    if [[ "$project_types" == "unknown" ]]; then
        info "No recognized manifest files found - skipping checks"
        return 0
    fi

    info "Detected project type(s): $project_types"
    echo ""

    # Export variables for sub-checks
    export PROJECT_TYPES="$project_types"
    export COMMIT_SUBJECT="$subject"
    export TF_SECRETS_BLOCKING TF_LOCKFILE_BLOCKING TF_CONFIG_BLOCKING
    export TF_LOGS_BLOCKING TF_PARITY_BLOCKING

    # Factor 2: Dependencies
    if [[ "$TF_DEPENDENCIES_ENABLED" == "true" ]]; then
        if has_override "no-lockfile" "$subject"; then
            info "[no-lockfile] tag found - skipping dependency check"
        else
            if ! run_check "dependencies" "$commit_msg_file"; then
                check_result=1
                if [[ "$TF_LOCKFILE_BLOCKING" == "true" ]]; then
                    failed=1
                fi
            fi
        fi
    fi

    # Factor 3: Config (secrets and hardcoded config)
    if [[ "$TF_CONFIG_ENABLED" == "true" ]]; then
        if has_override "no-secret-check" "$subject"; then
            info "[no-secret-check] tag found - skipping config check"
        else
            if ! run_check "config" "$commit_msg_file"; then
                check_result=1
                if [[ "$TF_SECRETS_BLOCKING" == "true" ]]; then
                    failed=1
                fi
            fi
        fi
    fi

    # Factor 11: Logs
    if [[ "$TF_LOGS_ENABLED" == "true" ]]; then
        if has_override "file-logs" "$subject"; then
            info "[file-logs] tag found - skipping logs check"
        else
            if ! run_check "logs" "$commit_msg_file"; then
                check_result=1
                if [[ "$TF_LOGS_BLOCKING" == "true" ]]; then
                    failed=1
                fi
            fi
        fi
    fi

    # Factor 10: Dev/Prod Parity
    if [[ "$TF_PARITY_ENABLED" == "true" ]]; then
        if has_override "env-branch" "$subject"; then
            info "[env-branch] tag found - skipping parity check"
        else
            if ! run_check "parity" "$commit_msg_file"; then
                check_result=1
                if [[ "$TF_PARITY_BLOCKING" == "true" ]]; then
                    failed=1
                fi
            fi
        fi
    fi

    # Summary
    echo ""
    if [[ $failed -gt 0 ]]; then
        error "12-factor compliance check failed"
        echo ""
        echo "See .claude/rules/twelve-factor.md for guidance."
        return 1
    elif [[ $WARNINGS -gt 0 ]]; then
        warn "12-factor compliance check completed with $WARNINGS warning(s)"
        return 0
    else
        success "12-factor compliance checks passed"
        return 0
    fi
}

main "$@"
