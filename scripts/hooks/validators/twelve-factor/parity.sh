#!/usr/bin/env bash
#
# parity.sh - Factor 10: Dev/Prod Parity
#
# Detects environment-specific branching patterns that can lead
# to differences between development and production environments.
#
# Warning patterns:
# - Ruby: Rails.env.production?, case Rails.env
# - Python: if settings.DEBUG, if ENVIRONMENT ==
# - Go: if os.Getenv("GO_ENV") ==
# - Node: if (process.env.NODE_ENV ===
#
# Context reduces severity (these are often acceptable):
# - Database/logging configuration files
# - Test setup files
# - Feature flag implementations
#
# Returns: 0 always (advisory only by default)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config.sh"

TF_PARITY_BLOCKING="${TF_PARITY_BLOCKING:-false}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "  ${GREEN}Parity:${NC} OK (no env branching)"
}

# Track findings
PARITY_WARNINGS=()

# Get staged files
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true
}

# Check if file is in acceptable context for env branching
is_acceptable_context() {
    local file="$1"

    # Test files - env branching is expected
    case "$file" in
        *_test.go|*_spec.rb|*.test.ts|*.test.js|*.spec.ts|*.spec.js)
            return 0
            ;;
        spec/*|test/*|tests/*|__tests__/*)
            return 0
            ;;
    esac

    # Configuration files - env branching is normal
    case "$file" in
        *config/*|*settings/*|*initializers/*)
            return 0
            ;;
        config.rb|settings.py|config.go|config.ts|config.js)
            return 0
            ;;
        database.yml|database.py|*_config.*)
            return 0
            ;;
    esac

    # Environment setup files
    case "$file" in
        *environment*|*environments/*)
            return 0
            ;;
    esac

    # Feature flag implementations
    case "$file" in
        *feature*|*flag*|*toggle*)
            return 0
            ;;
    esac

    return 1
}

# Scan file for environment branching patterns
scan_for_env_branching() {
    local file="$1"
    local line_num=0
    local ext="${file##*.}"

    # Skip binary files
    if file "$file" 2>/dev/null | grep -q 'binary'; then
        return
    fi

    # Skip acceptable contexts
    if is_acceptable_context "$file"; then
        return
    fi

    while IFS= read -r line; do
        ((line_num++))

        case "$ext" in
            rb)
                # Ruby/Rails environment checks
                if echo "$line" | grep -qE 'Rails\.env\.(production|development|staging|test)\?'; then
                    PARITY_WARNINGS+=("$file:$line_num - Rails.env.X? check")
                fi
                if echo "$line" | grep -qE 'case\s+Rails\.env'; then
                    PARITY_WARNINGS+=("$file:$line_num - case Rails.env switch")
                fi
                if echo "$line" | grep -qE 'if\s+Rails\.env\s*=='; then
                    PARITY_WARNINGS+=("$file:$line_num - Rails.env comparison")
                fi
                # ENV checks for environment
                if echo "$line" | grep -qE 'ENV\[['\''"]RAILS_ENV|RACK_ENV['\''"]'; then
                    PARITY_WARNINGS+=("$file:$line_num - RAILS_ENV/RACK_ENV check")
                fi
                ;;

            py)
                # Python/Django environment checks
                if echo "$line" | grep -qE 'settings\.DEBUG|DEBUG\s*==\s*True'; then
                    PARITY_WARNINGS+=("$file:$line_num - DEBUG mode check")
                fi
                if echo "$line" | grep -qE 'if\s+(ENVIRONMENT|ENV|DJANGO_ENV)\s*=='; then
                    PARITY_WARNINGS+=("$file:$line_num - Environment variable comparison")
                fi
                if echo "$line" | grep -qE 'os\.environ\.get\s*\(['\''"].*ENV['\''"]'; then
                    # Only flag if comparing to environment names
                    if echo "$line" | grep -qE '(production|development|staging)'; then
                        PARITY_WARNINGS+=("$file:$line_num - Environment name check")
                    fi
                fi
                ;;

            go)
                # Go environment checks
                if echo "$line" | grep -qE 'os\.Getenv\s*\(['\''"].*ENV['\''"]'; then
                    if echo "$line" | grep -qE '(production|development|staging)'; then
                        PARITY_WARNINGS+=("$file:$line_num - Environment name check")
                    fi
                fi
                if echo "$line" | grep -qE 'if\s+.*[Ee]nv\s*==\s*['\''"]production'; then
                    PARITY_WARNINGS+=("$file:$line_num - Production environment check")
                fi
                ;;

            ts|tsx|js|jsx)
                # Node.js environment checks
                if echo "$line" | grep -qE 'process\.env\.NODE_ENV\s*===?\s*['\''"]'; then
                    PARITY_WARNINGS+=("$file:$line_num - NODE_ENV comparison")
                fi
                if echo "$line" | grep -qE 'if\s*\(\s*process\.env\.NODE_ENV'; then
                    PARITY_WARNINGS+=("$file:$line_num - NODE_ENV conditional")
                fi
                # Common env check patterns
                if echo "$line" | grep -qE 'isDevelopment|isProduction|isProd|isDev'; then
                    PARITY_WARNINGS+=("$file:$line_num - Environment flag variable")
                fi
                ;;
        esac

    done < "$file"
}

# Main
main() {
    local staged_files
    local has_warnings=0

    # Get staged files and scan
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        scan_for_env_branching "$file"
    done <<< "$staged_files"

    # Report findings
    if [[ ${#PARITY_WARNINGS[@]} -gt 0 ]]; then
        echo ""
        warn "Environment-specific branching detected (Factor 10: Dev/Prod Parity)"
        for msg in "${PARITY_WARNINGS[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "12-factor apps should behave consistently across environments."
        echo "Consider using feature flags or configuration instead of env checks."
        echo ""
        echo "Acceptable in: config files, test setup, feature flag implementations."
        echo "Use [env-branch] override to acknowledge this pattern."
        has_warnings=1
    fi

    if [[ $has_warnings -eq 0 ]]; then
        success
    fi

    # Return failure only if blocking is enabled
    if [[ "$TF_PARITY_BLOCKING" == "true" ]] && [[ $has_warnings -gt 0 ]]; then
        return 1
    fi

    return 0
}

main "$@"
