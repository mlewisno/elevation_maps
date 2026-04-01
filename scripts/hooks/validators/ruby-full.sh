#!/usr/bin/env bash
#
# ruby-full.sh - Full-project Ruby/Rails validation
#
# Runs RuboCop on entire project and full test suite.
# Intended for pre-push to match CI checks exactly.
#
# Usage: ruby-full.sh
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

RUBOCOP_ENABLED=true
MINITEST_ENABLED=true
SYSTEM_TESTS_ENABLED=false
RSPEC_ENABLED=false

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

error() { echo -e "${RED}ERROR:${NC} $1" >&2; }
warn() { echo -e "${YELLOW}WARNING:${NC} $1" >&2; }
success() { echo -e "${GREEN}OK:${NC} $1"; }
info() { echo -e "${CYAN}INFO:${NC} $1"; }

check_bundle() {
    if ! command -v bundle &> /dev/null; then
        warn "bundler not found - skipping Ruby validation"
        return 1
    fi

    if [[ ! -f "Gemfile" ]]; then
        warn "No Gemfile found - skipping Ruby validation"
        return 1
    fi

    return 0
}

main() {
    local failed=0

    if ! check_bundle; then
        return 0
    fi

    # Run RuboCop on full project
    if [[ "$RUBOCOP_ENABLED" == "true" ]]; then
        if bundle show rubocop &> /dev/null; then
            info "Running RuboCop on full project..."
            if bundle exec rubocop; then
                success "RuboCop passed (full project)"
            else
                error "RuboCop found issues"
                echo ""
                echo "To auto-fix safe issues: bundle exec rubocop -a"
                failed=$((failed + 1))
            fi
        else
            warn "rubocop not in bundle - skipping"
        fi
    fi

    # Run full test suite
    if [[ "$MINITEST_ENABLED" == "true" ]]; then
        info "Running full test suite..."
        if bin/rails test 2>&1; then
            success "Tests passed"
        else
            error "Tests failed"
            failed=$((failed + 1))
        fi
    fi

    # Run system tests (Capybara)
    if [[ "$SYSTEM_TESTS_ENABLED" == "true" ]] && [[ "$MINITEST_ENABLED" == "true" ]]; then
        info "Running system tests..."
        if bin/rails test:system 2>&1; then
            success "System tests passed"
        else
            error "System tests failed"
            failed=$((failed + 1))
        fi
    fi

    if [[ "$RSPEC_ENABLED" == "true" ]]; then
        info "Running full spec suite..."
        if bundle exec rspec; then
            success "Specs passed"
        else
            error "Specs failed"
            failed=$((failed + 1))
        fi
    fi

    if [[ $failed -gt 0 ]]; then
        error "Full Ruby validation failed"
        return 1
    fi

    success "Full Ruby validation passed"
    return 0
}

main "$@"
