#!/usr/bin/env bash
#
# dependencies.sh - Factor 2: Dependencies
#
# Checks that explicit dependency manifests have accompanying lockfiles.
# Lockfiles ensure reproducible builds across environments.
#
# Supported languages:
# - Ruby: Gemfile -> Gemfile.lock
# - Python: pyproject.toml -> uv.lock or poetry.lock, Pipfile -> Pipfile.lock
# - Go: go.mod -> go.sum
# - Node: package.json -> package-lock.json, yarn.lock, or pnpm-lock.yaml
#
# Returns: 0 if all lockfiles present, 1 if missing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config.sh"

TF_LOCKFILE_BLOCKING="${TF_LOCKFILE_BLOCKING:-true}"

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
    echo -e "  ${GREEN}Dependencies:${NC} OK (lockfiles present)"
}

# Track issues
MISSING_LOCKFILES=()
OUTDATED_LOCKFILES=()

# Check if a file is staged for commit
is_staged() {
    git diff --cached --name-only 2>/dev/null | grep -q "^$1$"
}

# Check Ruby dependencies
check_ruby() {
    if [[ ! -f "Gemfile" ]]; then
        return 0
    fi

    if [[ ! -f "Gemfile.lock" ]]; then
        MISSING_LOCKFILES+=("Gemfile.lock (run: bundle install)")
        return 1
    fi

    # Check if Gemfile changed but lockfile didn't
    if is_staged "Gemfile" && ! is_staged "Gemfile.lock"; then
        OUTDATED_LOCKFILES+=("Gemfile.lock may be outdated (Gemfile changed)")
    fi

    return 0
}

# Check Python dependencies
check_python() {
    local has_issue=0

    # pyproject.toml projects: check for uv.lock or poetry.lock
    if [[ -f "pyproject.toml" ]]; then
        if [[ -f "uv.lock" ]]; then
            # uv project
            if is_staged "pyproject.toml" && ! is_staged "uv.lock"; then
                OUTDATED_LOCKFILES+=("uv.lock may be outdated (pyproject.toml changed, run: uv lock)")
            fi
        elif grep -q '\[tool.poetry\]' pyproject.toml 2>/dev/null; then
            # Poetry project
            if [[ ! -f "poetry.lock" ]]; then
                MISSING_LOCKFILES+=("poetry.lock (run: poetry lock)")
                has_issue=1
            elif is_staged "pyproject.toml" && ! is_staged "poetry.lock"; then
                OUTDATED_LOCKFILES+=("poetry.lock may be outdated (pyproject.toml changed)")
            fi
        fi
    fi

    # Pipenv: Pipfile -> Pipfile.lock
    if [[ -f "Pipfile" ]]; then
        if [[ ! -f "Pipfile.lock" ]]; then
            MISSING_LOCKFILES+=("Pipfile.lock (run: pipenv lock)")
            has_issue=1
        elif is_staged "Pipfile" && ! is_staged "Pipfile.lock"; then
            OUTDATED_LOCKFILES+=("Pipfile.lock may be outdated (Pipfile changed)")
        fi
    fi

    # Note: requirements.txt doesn't have a separate lockfile concept
    # but pip-compile can generate requirements.txt from requirements.in
    if [[ -f "requirements.in" ]] && [[ ! -f "requirements.txt" ]]; then
        MISSING_LOCKFILES+=("requirements.txt (run: pip-compile)")
        has_issue=1
    fi

    return $has_issue
}

# Check Go dependencies
check_go() {
    if [[ ! -f "go.mod" ]]; then
        return 0
    fi

    if [[ ! -f "go.sum" ]]; then
        MISSING_LOCKFILES+=("go.sum (run: go mod tidy)")
        return 1
    fi

    # Check if go.mod changed but go.sum didn't
    if is_staged "go.mod" && ! is_staged "go.sum"; then
        OUTDATED_LOCKFILES+=("go.sum may be outdated (go.mod changed)")
    fi

    return 0
}

# Check Node.js dependencies
check_node() {
    if [[ ! -f "package.json" ]]; then
        return 0
    fi

    # Accept any of the common lockfiles
    if [[ ! -f "package-lock.json" ]] && [[ ! -f "yarn.lock" ]] && [[ ! -f "pnpm-lock.yaml" ]]; then
        MISSING_LOCKFILES+=("package-lock.json (or yarn.lock/pnpm-lock.yaml)")
        return 1
    fi

    # Check for potential lockfile staleness
    if is_staged "package.json"; then
        local lockfile_staged=false
        if is_staged "package-lock.json" || is_staged "yarn.lock" || is_staged "pnpm-lock.yaml"; then
            lockfile_staged=true
        fi
        if [[ "$lockfile_staged" == "false" ]]; then
            OUTDATED_LOCKFILES+=("Node lockfile may be outdated (package.json changed)")
        fi
    fi

    return 0
}

# Main
main() {
    local has_error=0

    # Run checks based on detected project types
    check_ruby || has_error=1
    check_python || has_error=1
    check_go || has_error=1
    check_node || has_error=1

    # Report missing lockfiles (blocking errors)
    if [[ ${#MISSING_LOCKFILES[@]} -gt 0 ]]; then
        echo ""
        error "Missing lockfile(s) (Factor 2: Dependencies)"
        for msg in "${MISSING_LOCKFILES[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "Lockfiles ensure reproducible builds across environments."
        echo "Generate them before committing dependency changes."
        echo ""
        echo "Use [no-lockfile] override if this is intentional."
        has_error=1
    fi

    # Report potentially outdated lockfiles (warnings)
    if [[ ${#OUTDATED_LOCKFILES[@]} -gt 0 ]]; then
        echo ""
        warn "Potential lockfile staleness (Factor 2: Dependencies)"
        for msg in "${OUTDATED_LOCKFILES[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "If you modified dependencies, regenerate the lockfile."
    fi

    if [[ $has_error -eq 0 ]] && [[ ${#OUTDATED_LOCKFILES[@]} -eq 0 ]]; then
        success
    fi

    if [[ "$TF_LOCKFILE_BLOCKING" == "true" ]] && [[ $has_error -gt 0 ]]; then
        return 1
    fi

    return 0
}

main "$@"
