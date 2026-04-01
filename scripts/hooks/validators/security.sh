#!/usr/bin/env bash
#
# security.sh - Security scanning validation
#
# Runs:
# - Brakeman for Rails security vulnerabilities
# - Bundler Audit for gem vulnerability scanning
# - Importmap Audit for JS dependency security
#
# Supports monorepos: automatically discovers app roots from changed
# files and runs security checks in each.
#
# Usage: security.sh
# Returns: 0 on success, 1 on failure

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

# Defaults
BRAKEMAN_ENABLED=true
BUNDLER_AUDIT_ENABLED=true
IMPORTMAP_AUDIT_ENABLED=true

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

# Find nearest ancestor directory containing a Gemfile.
# Walks up from the file's directory toward the repo root.
find_gemfile_dir() {
    local file="$1"
    local dir
    dir=$(dirname "$file")

    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        if [[ -f "$dir/Gemfile" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    # Check repo root
    if [[ -f "Gemfile" ]]; then
        echo "."
        return 0
    fi

    return 1
}

# Find app roots from changed files.
# Returns unique directories containing Gemfiles that have changed files.
find_changed_app_roots() {
    local changed_files
    changed_files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

    if [[ -z "$changed_files" ]]; then
        return 0
    fi

    local roots=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local root
        root=$(find_gemfile_dir "$file") || continue

        # Deduplicate
        local found=false
        for existing in "${roots[@]+"${roots[@]}"}"; do
            if [[ "$existing" == "$root" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            roots+=("$root")
        fi
    done <<< "$changed_files"

    for root in "${roots[@]+"${roots[@]}"}"; do
        echo "$root"
    done
}

# Run Brakeman security scanner (from within app root)
run_brakeman() {
    local app_root="$1"

    (
        cd "$app_root"

        if ! bundle show brakeman &> /dev/null; then
            warn "brakeman not in bundle ($app_root) - skipping"
            exit 0
        fi

        info "Running Brakeman security scan..."

        if bundle exec brakeman --no-pager -q; then
            success "Brakeman passed"
        else
            error "Brakeman found security issues"
            echo ""
            echo "Run '(cd $app_root && bundle exec brakeman)' for detailed report"
            exit 1
        fi
    )
}

# Run Bundler Audit for gem vulnerabilities (from within app root)
run_bundler_audit() {
    local app_root="$1"

    (
        cd "$app_root"

        if ! bundle show bundler-audit &> /dev/null; then
            warn "bundler-audit not in bundle ($app_root) - skipping"
            exit 0
        fi

        info "Running Bundler Audit..."

        if bundle exec bundler-audit check --update; then
            success "Bundler Audit passed"
        else
            error "Bundler Audit found vulnerable gems"
            echo ""
            echo "Run '(cd $app_root && bundle exec bundler-audit)' for details"
            exit 1
        fi
    )
}

# Run Importmap Audit for JS dependency security (from within app root)
run_importmap_audit() {
    local app_root="$1"

    (
        cd "$app_root"

        if [[ ! -f "bin/importmap" ]]; then
            info "No bin/importmap found - skipping importmap audit"
            exit 0
        fi

        if [[ ! -f "config/importmap.rb" ]]; then
            info "No importmap.rb found - skipping importmap audit"
            exit 0
        fi

        info "Running Importmap Audit..."

        if bin/importmap audit; then
            success "Importmap Audit passed"
        else
            error "Importmap Audit found vulnerable packages"
            echo ""
            echo "Run '(cd $app_root && bin/importmap audit)' for details"
            exit 1
        fi
    )
}

# Main
main() {
    local failed=0

    echo ""
    echo "Running security checks..."
    echo ""

    # Find app roots from changed files
    local app_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && app_roots+=("$root")
    done <<< "$(find_changed_app_roots)"

    if [[ ${#app_roots[@]} -eq 0 ]]; then
        info "No app roots with changed files found - skipping security validation"
        return 0
    fi

    if ! command -v bundle &> /dev/null; then
        warn "bundler not found - skipping security validation"
        return 0
    fi

    # Run security checks per app root
    for app_root in "${app_roots[@]}"; do
        if [[ "$app_root" != "." ]]; then
            echo "App root: $app_root"
            echo ""
        fi

        # Run Brakeman
        if [[ "$BRAKEMAN_ENABLED" == "true" ]]; then
            run_brakeman "$app_root" || failed=$((failed + 1))
        fi

        # Run Bundler Audit
        if [[ "$BUNDLER_AUDIT_ENABLED" == "true" ]]; then
            run_bundler_audit "$app_root" || failed=$((failed + 1))
        fi

        # Run Importmap Audit
        if [[ "$IMPORTMAP_AUDIT_ENABLED" == "true" ]]; then
            run_importmap_audit "$app_root" || failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "Security validation failed"
        return 1
    fi

    success "Security validation passed"
    return 0
}

main "$@"
