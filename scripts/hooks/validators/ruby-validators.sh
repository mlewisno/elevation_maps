#!/usr/bin/env bash
#
# ruby-validators.sh - Run RSpec tests for Ruby validators
#
# Runs the Ruby validator test suite with coverage checking.
# This ensures the validators themselves are tested.
#
# Usage: ruby-validators.sh
# Returns: 0 on success, 1 on test failure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

RUBY_VALIDATORS_ENABLED=true
RUBY_VALIDATORS_BLOCKING=true

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Find project root
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.claude" ]] || [[ -d "$dir/scripts/validators" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "$PWD"
}

PROJECT_ROOT=$(find_project_root)
VALIDATORS_DIR="$PROJECT_ROOT/scripts/validators"

main() {
    if [[ "$RUBY_VALIDATORS_ENABLED" != "true" ]]; then
        info "Ruby validators check is disabled"
        return 0
    fi

    # Check if validators directory exists
    if [[ ! -d "$VALIDATORS_DIR" ]]; then
        info "No validators directory found - skipping"
        return 0
    fi

    # Check if Gemfile exists
    if [[ ! -f "$VALIDATORS_DIR/Gemfile" ]]; then
        info "No Gemfile in validators directory - skipping"
        return 0
    fi

    # Check if bundle is available
    if ! command -v bundle &>/dev/null; then
        info "bundler not found - skipping Ruby validators check"
        return 0
    fi

    # Check if there are any staged Ruby validator changes
    local staged_changes
    staged_changes=$(git diff --cached --name-only 2>/dev/null | grep -E '^scripts/validators/' || true)

    if [[ -z "$staged_changes" ]]; then
        info "No changes to Ruby validators - skipping"
        return 0
    fi

    echo ""
    info "Running Ruby validator tests..."
    echo ""

    # Run RSpec
    cd "$VALIDATORS_DIR"

    if bundle exec rspec --format progress; then
        success "Ruby validator tests passed"
        return 0
    else
        error "Ruby validator tests failed"
        if [[ "$RUBY_VALIDATORS_BLOCKING" == "true" ]]; then
            echo ""
            echo "Fix failing tests before pushing."
            return 1
        fi
        return 0
    fi
}

main "$@"
