#!/usr/bin/env bash
#
# coverage-check.sh - Test coverage validation
#
# Runs:
# - SimpleCov coverage analysis from last test run
# - Undercover for diff-aware coverage (optional)
#
# Usage: coverage-check.sh [commit-msg-file]
# Returns: 0 on success, 1 on failure (if blocking mode enabled)
#
# Override: Add [no-coverage] to commit message to skip

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
COVERAGE_ENABLED=true
COVERAGE_BLOCKING=false
COVERAGE_MIN_THRESHOLD=80
UNDERCOVER_ENABLED=false
UNDERCOVER_COMPARE_BRANCH=main

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

# Check for [no-coverage] override in commit subject line
has_override() {
    local commit_msg_file="${1:-}"

    # Check first line of commit message file (subject line only)
    if [[ -n "$commit_msg_file" ]] && [[ -f "$commit_msg_file" ]]; then
        if head -1 "$commit_msg_file" | grep -qE '\[no-coverage\]'; then
            return 0
        fi
    fi

    # Also check the last commit subject if we're in pre-push
    if git log -1 --pretty=%s 2>/dev/null | grep -qE '\[no-coverage\]'; then
        return 0
    fi

    return 1
}

# Check if bundle is available and Gemfile exists
check_bundle() {
    if ! command -v bundle &> /dev/null; then
        warn "bundler not found - skipping coverage validation"
        return 1
    fi

    if [[ ! -f "Gemfile" ]]; then
        warn "No Gemfile found - skipping coverage validation"
        return 1
    fi

    return 0
}

# Check if SimpleCov is in the bundle
check_simplecov() {
    if ! bundle show simplecov &> /dev/null; then
        warn "simplecov not in bundle - skipping coverage check"
        echo "  Add to Gemfile: gem 'simplecov', require: false, group: :test"
        return 1
    fi
    return 0
}

# Check if coverage results exist and are recent
check_coverage_results() {
    local coverage_file="coverage/.last_run.json"

    if [[ ! -f "$coverage_file" ]]; then
        warn "No coverage results found at $coverage_file"
        echo "  Run 'bundle exec rspec' to generate coverage data"
        return 1
    fi

    # Check if coverage results are stale (older than 1 hour)
    local file_age
    if [[ "$(uname)" == "Darwin" ]]; then
        file_age=$(( $(date +%s) - $(stat -f %m "$coverage_file") ))
    else
        file_age=$(( $(date +%s) - $(stat -c %Y "$coverage_file") ))
    fi

    if [[ $file_age -gt 3600 ]]; then
        warn "Coverage results are over 1 hour old"
        echo "  Run tests again for current coverage: bundle exec rspec"
    fi

    return 0
}

# Parse coverage percentage from SimpleCov's last_run.json
get_coverage_percentage() {
    local coverage_file="coverage/.last_run.json"

    if [[ ! -f "$coverage_file" ]]; then
        echo "0"
        return 1
    fi

    # Extract line coverage percentage using grep/sed (portable)
    # Format: {"result":{"line":87.5,...}}
    local coverage
    coverage=$(grep -oE '"line":[0-9]+\.?[0-9]*' "$coverage_file" | head -1 | sed 's/"line"://')

    if [[ -z "$coverage" ]]; then
        # Try older format or branch coverage
        coverage=$(grep -oE '"covered_percent":[0-9]+\.?[0-9]*' "$coverage_file" | head -1 | sed 's/"covered_percent"://')
    fi

    if [[ -z "$coverage" ]]; then
        echo "0"
        return 1
    fi

    echo "$coverage"
}

# Run Undercover for diff-aware coverage
run_undercover() {
    if ! bundle show undercover &> /dev/null; then
        warn "undercover not in bundle - skipping diff-aware coverage"
        echo "  Add to Gemfile: gem 'undercover', require: false, group: :test"
        return 0
    fi

    # Check for LCOV format coverage (required by Undercover)
    if [[ ! -f "coverage/lcov.info" ]] && [[ ! -f "coverage/lcov/project.lcov" ]]; then
        warn "No LCOV coverage file found for Undercover"
        echo "  Configure SimpleCov with simplecov-lcov formatter"
        return 0
    fi

    local compare_branch="${UNDERCOVER_COMPARE_BRANCH}"

    # Check if compare branch exists
    if ! git rev-parse --verify "origin/$compare_branch" &>/dev/null; then
        if ! git rev-parse --verify "$compare_branch" &>/dev/null; then
            warn "Compare branch '$compare_branch' not found - skipping Undercover"
            return 0
        fi
        compare_branch="$compare_branch"
    else
        compare_branch="origin/$compare_branch"
    fi

    info "Running Undercover (comparing against $compare_branch)..."

    local undercover_output
    local undercover_exit=0
    undercover_output=$(bundle exec undercover --compare "$compare_branch" 2>&1) || undercover_exit=$?

    if [[ $undercover_exit -eq 0 ]]; then
        success "Undercover passed - changed code is covered"
        return 0
    fi

    echo ""
    warn "Undercover found uncovered changes:"
    echo "$undercover_output" | head -30
    echo ""

    if [[ "$COVERAGE_BLOCKING" == "true" ]]; then
        error "Diff coverage check failed"
        echo "  Add tests for uncovered changes, or use [no-coverage] to skip"
        return 1
    else
        warn "Coverage warning - add tests for uncovered code"
        echo "  Use [no-coverage] in commit message to suppress this warning"
        return 0
    fi
}

# Analyze SimpleCov results
analyze_simplecov() {
    local coverage
    coverage=$(get_coverage_percentage)

    if [[ "$coverage" == "0" ]]; then
        warn "Could not parse coverage results"
        return 0
    fi

    local threshold="$COVERAGE_MIN_THRESHOLD"
    local coverage_int="${coverage%.*}"  # Truncate to integer for comparison

    echo ""
    echo "Coverage analysis:"
    echo "  Overall: ${coverage}% (threshold: ${threshold}%)"
    echo ""

    if [[ "$coverage_int" -ge "$threshold" ]]; then
        success "Coverage meets threshold"
        return 0
    fi

    # Coverage below threshold
    warn "Coverage below threshold: ${coverage}% < ${threshold}%"

    # Try to show low coverage files if detailed report exists
    if [[ -f "coverage/index.html" ]]; then
        echo "  View detailed report: open coverage/index.html"
    fi

    if [[ "$COVERAGE_BLOCKING" == "true" ]]; then
        error "Coverage check failed"
        echo ""
        echo "Options:"
        echo "  1. Add tests to improve coverage"
        echo "  2. Add [no-coverage] to commit message to skip"
        return 1
    else
        echo ""
        echo "  Add [no-coverage] to commit message to suppress this warning"
        return 0
    fi
}

# Main
main() {
    local commit_msg_file="${1:-}"

    # Check if coverage is enabled
    if [[ "$COVERAGE_ENABLED" != "true" ]]; then
        return 0
    fi

    # Check for override first
    if has_override "$commit_msg_file"; then
        info "Found [no-coverage] tag - skipping coverage check"
        return 0
    fi

    echo ""
    echo "Running coverage checks..."

    # Check prerequisites
    if ! check_bundle; then
        return 0
    fi

    if ! check_simplecov; then
        return 0
    fi

    if ! check_coverage_results; then
        # No coverage results - warn but don't fail
        return 0
    fi

    local failed=0

    # Run Undercover if enabled (diff-aware coverage)
    if [[ "$UNDERCOVER_ENABLED" == "true" ]]; then
        run_undercover || failed=$((failed + 1))
    else
        # Fall back to SimpleCov overall analysis
        analyze_simplecov || failed=$((failed + 1))
    fi

    if [[ $failed -gt 0 ]]; then
        return 1
    fi

    return 0
}

main "$@"
