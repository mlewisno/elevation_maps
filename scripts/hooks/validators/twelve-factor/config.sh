#!/usr/bin/env bash
#
# config.sh - Factor 3: Config
#
# Detects hardcoded secrets and configuration that should be
# stored in environment variables per 12-factor principles.
#
# Blocking patterns (high confidence secrets):
# - AWS access keys
# - Stripe API keys
# - GitHub tokens
# - Generic secrets with values
# - Sensitive files (.env, *.pem, *.key)
#
# Warning patterns (config in code):
# - Database URLs
# - Localhost URLs in production code
#
# Returns: 1 if blocking secrets found, 0 otherwise

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config.sh"

TF_SECRETS_BLOCKING="${TF_SECRETS_BLOCKING:-true}"
TF_CONFIG_BLOCKING="${TF_CONFIG_BLOCKING:-false}"

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
    echo -e "  ${GREEN}Config:${NC} OK (no secrets detected)"
}

# Track findings
SECRETS_FOUND=()
CONFIG_WARNINGS=()
SENSITIVE_FILES=()

# Get staged files
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true
}

# Check if file should be excluded from scanning
should_exclude() {
    local file="$1"

    # Test files - likely contain test data
    case "$file" in
        *_test.go|*_spec.rb|*.test.ts|*.test.tsx|*.test.js|*.spec.ts|*.spec.js)
            return 0
            ;;
        spec/*|test/*|tests/*|__tests__/*)
            return 0
            ;;
    esac

    # Documentation
    case "$file" in
        *.md|*.rst|*.txt)
            return 0
            ;;
    esac

    # Example/template files
    case "$file" in
        *.example|*.sample|*.template|.env.example|.env.sample)
            return 0
            ;;
    esac

    return 1
}

# Check for sensitive files being committed
check_sensitive_files() {
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        case "$file" in
            .env|.env.local|.env.production|.env.development)
                # .env.example is OK, actual .env files are not
                if [[ "$file" != *.example ]] && [[ "$file" != *.sample ]]; then
                    SENSITIVE_FILES+=("$file (environment file with secrets)")
                fi
                ;;
            *.pem|*.key|*.p12|*.pfx)
                SENSITIVE_FILES+=("$file (private key/certificate)")
                ;;
            credentials.json|secrets.json|*credentials*.json)
                SENSITIVE_FILES+=("$file (credentials file)")
                ;;
            id_rsa|id_ed25519|id_dsa)
                SENSITIVE_FILES+=("$file (SSH private key)")
                ;;
            .htpasswd|.pgpass|.netrc)
                SENSITIVE_FILES+=("$file (password file)")
                ;;
        esac
    done <<< "$staged_files"
}

# Scan file content for secrets
scan_for_secrets() {
    local file="$1"
    local line_num=0
    local findings=()

    # Skip binary files
    if file "$file" | grep -q 'binary'; then
        return
    fi

    while IFS= read -r line; do
        ((line_num++))

        # AWS Access Key ID
        if echo "$line" | grep -qE 'AKIA[0-9A-Z]{16}'; then
            findings+=("$file:$line_num - AWS Access Key ID detected")
        fi

        # AWS Secret Access Key (40 char base64)
        if echo "$line" | grep -qE '(aws_secret_access_key|AWS_SECRET)[[:space:]]*[=:][[:space:]]*['\''"]?[A-Za-z0-9/+=]{40}'; then
            findings+=("$file:$line_num - AWS Secret Access Key pattern")
        fi

        # Stripe keys
        if echo "$line" | grep -qE 'sk_live_[a-zA-Z0-9]{24,}'; then
            findings+=("$file:$line_num - Stripe live secret key")
        fi
        if echo "$line" | grep -qE 'sk_test_[a-zA-Z0-9]{24,}'; then
            findings+=("$file:$line_num - Stripe test secret key (still sensitive)")
        fi
        if echo "$line" | grep -qE 'rk_live_[a-zA-Z0-9]{24,}'; then
            findings+=("$file:$line_num - Stripe restricted key")
        fi

        # GitHub tokens
        if echo "$line" | grep -qE 'ghp_[a-zA-Z0-9]{36,}'; then
            findings+=("$file:$line_num - GitHub personal access token")
        fi
        if echo "$line" | grep -qE 'gho_[a-zA-Z0-9]{36,}'; then
            findings+=("$file:$line_num - GitHub OAuth token")
        fi
        if echo "$line" | grep -qE 'github_pat_[a-zA-Z0-9_]{22,}'; then
            findings+=("$file:$line_num - GitHub fine-grained PAT")
        fi

        # Generic secret patterns (high confidence)
        # Match: password = "value" or password: "value" with actual values
        if echo "$line" | grep -qiE '(password|passwd|secret|api_key|apikey|access_token)[[:space:]]*[=:][[:space:]]*['\''"][^'\''"]{8,}['\''"]'; then
            # Exclude placeholder values
            if ! echo "$line" | grep -qiE '(password|secret|api_key)[[:space:]]*[=:][[:space:]]*['\''"]?(your[_-]|xxx|placeholder|changeme|TODO|FIXME|\$\{|ENV\[|process\.env|os\.environ|os\.Getenv)'; then
                findings+=("$file:$line_num - Hardcoded secret value")
            fi
        fi

        # Private keys embedded in code
        if echo "$line" | grep -qE '^-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
            findings+=("$file:$line_num - Embedded private key")
        fi

    done < "$file"

    SECRETS_FOUND+=("${findings[@]}")
}

# Scan for config warnings (not blocking by default)
scan_for_config() {
    local file="$1"
    local line_num=0

    # Skip binary files
    if file "$file" | grep -q 'binary'; then
        return
    fi

    while IFS= read -r line; do
        ((line_num++))

        # Database connection strings with credentials
        if echo "$line" | grep -qE '(postgres|mysql|mongodb|redis)://[^:]+:[^@]+@'; then
            CONFIG_WARNINGS+=("$file:$line_num - Database URL with credentials")
        fi

        # Hardcoded localhost URLs (might indicate dev-only code)
        if echo "$line" | grep -qE 'https?://(localhost|127\.0\.0\.1):[0-9]+'; then
            # Skip if in test file or config file
            if [[ ! "$file" =~ (config|settings|test|spec) ]]; then
                CONFIG_WARNINGS+=("$file:$line_num - Hardcoded localhost URL")
            fi
        fi

    done < "$file"
}

# Main
main() {
    local staged_files
    local has_secrets=0
    local has_config_issues=0

    # Check for sensitive files first
    check_sensitive_files

    # Get staged files and scan content
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        # Skip excluded files
        if should_exclude "$file"; then
            continue
        fi

        scan_for_secrets "$file"
        scan_for_config "$file"
    done <<< "$staged_files"

    # Report sensitive files (blocking)
    if [[ ${#SENSITIVE_FILES[@]} -gt 0 ]]; then
        echo ""
        error "Sensitive files staged (Factor 3: Config)"
        for msg in "${SENSITIVE_FILES[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "These files should be in .gitignore, not committed."
        echo "Add them to .gitignore and unstage with: git reset HEAD <file>"
        has_secrets=1
    fi

    # Report secrets found in code (blocking)
    if [[ ${#SECRETS_FOUND[@]} -gt 0 ]]; then
        echo ""
        error "Potential secrets detected (Factor 3: Config)"
        for msg in "${SECRETS_FOUND[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "Secrets must be stored in environment variables, not code."
        echo ""
        echo "Fix: Use ENV.fetch('VAR_NAME') (Ruby), os.environ['VAR'] (Python),"
        echo "     os.Getenv('VAR') (Go), or process.env.VAR (Node)"
        echo ""
        echo "Use [no-secret-check] override only if these are false positives."
        has_secrets=1
    fi

    # Report config warnings (advisory)
    if [[ ${#CONFIG_WARNINGS[@]} -gt 0 ]]; then
        echo ""
        warn "Configuration patterns detected (Factor 3: Config)"
        for msg in "${CONFIG_WARNINGS[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "Consider using environment variables for these values."
        has_config_issues=1
    fi

    # Success message if no issues
    if [[ $has_secrets -eq 0 ]] && [[ $has_config_issues -eq 0 ]]; then
        success
    fi

    # Return failure only if blocking
    if [[ "$TF_SECRETS_BLOCKING" == "true" ]] && [[ $has_secrets -gt 0 ]]; then
        return 1
    fi

    if [[ "$TF_CONFIG_BLOCKING" == "true" ]] && [[ $has_config_issues -gt 0 ]]; then
        return 1
    fi

    return 0
}

main "$@"
