#!/usr/bin/env bash
#
# python-security.sh - Python security scanning validation
#
# Runs:
# - Bandit for Python security vulnerability scanning (SAST)
# - pip-audit for dependency vulnerability checking
#
# Supports monorepos: automatically discovers project roots from changed
# files and runs security checks in each.
#
# Usage: python-security.sh
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
BANDIT_ENABLED=true
PIP_AUDIT_ENABLED=true

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

# Find nearest ancestor directory containing a Python project marker.
# Checks for pyproject.toml, setup.py, setup.cfg, or requirements.txt.
find_python_root() {
    local file="$1"
    local dir
    dir=$(dirname "$file")

    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        for marker in pyproject.toml setup.py setup.cfg; do
            if [[ -f "$dir/$marker" ]]; then
                echo "$dir"
                return 0
            fi
        done
        dir=$(dirname "$dir")
    done

    # Check repo root
    for marker in pyproject.toml setup.py setup.cfg; do
        if [[ -f "$marker" ]]; then
            echo "."
            return 0
        fi
    done

    # Fall back to requirements.txt
    dir=$(dirname "$file")
    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        if [[ -f "$dir/requirements.txt" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    if [[ -f "requirements.txt" ]]; then
        echo "."
        return 0
    fi

    return 1
}

# Find app roots from changed files.
# Returns unique directories containing Python projects that have changed files.
find_changed_app_roots() {
    local changed_files
    changed_files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.py$' || true)

    if [[ -z "$changed_files" ]]; then
        return 0
    fi

    local roots=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local root
        root=$(find_python_root "$file") || continue

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

# Set up virtualenv if available (for tool discovery)
setup_venv() {
    local app_root="$1"

    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        return 0
    fi

    for venv_dir in .venv venv; do
        if [[ -d "$app_root/$venv_dir/bin" ]]; then
            export PATH="$app_root/$venv_dir/bin:$PATH"
            return 0
        fi
    done

    return 0
}

# Run Bandit security scanner
run_bandit() {
    local app_root="$1"

    (
        cd "$app_root"

        if ! command -v bandit &> /dev/null; then
            warn "bandit not found ($app_root) - skipping SAST scan"
            warn "Install with: pip install bandit"
            exit 0
        fi

        # Determine scan targets: prefer src/ if it exists, otherwise scan
        # Python files at root (excluding tests and venvs)
        local scan_targets=()
        if [[ -d "src" ]]; then
            scan_targets+=("src")
        fi
        # Also scan any top-level Python packages
        for dir in */; do
            dir="${dir%/}"
            if [[ -f "$dir/__init__.py" && "$dir" != "test" && "$dir" != "tests" && "$dir" != ".venv" && "$dir" != "venv" ]]; then
                scan_targets+=("$dir")
            fi
        done

        if [[ ${#scan_targets[@]} -eq 0 ]]; then
            # Fall back to scanning all .py files excluding tests/venvs
            scan_targets=(".")
        fi

        info "Running Bandit security scan..."

        local bandit_opts=("-r" "--exclude" ".venv,venv,tests,test")

        # Use project config if available
        if [[ -f ".bandit" ]]; then
            bandit_opts+=("--ini" ".bandit")
        elif [[ -f "bandit.yaml" ]]; then
            bandit_opts+=("-c" "bandit.yaml")
        fi

        if bandit "${bandit_opts[@]}" "${scan_targets[@]}"; then
            success "Bandit passed"
        else
            error "Bandit found security issues"
            echo ""
            echo "Run '(cd $app_root && bandit -r .)' for detailed report"
            exit 1
        fi
    )
}

# Run pip-audit for dependency vulnerability checking
run_pip_audit() {
    local app_root="$1"

    (
        cd "$app_root"

        if ! command -v pip-audit &> /dev/null; then
            warn "pip-audit not found ($app_root) - skipping dependency audit"
            warn "Install with: pip install pip-audit"
            exit 0
        fi

        info "Running pip-audit dependency check..."

        local audit_opts=()

        # Determine requirements source
        if [[ -f "pyproject.toml" ]]; then
            # pip-audit can scan the installed environment by default,
            # or use -r for requirements files
            if [[ -f "requirements.txt" ]]; then
                audit_opts+=("-r" "requirements.txt")
            fi
            # Otherwise pip-audit scans the current environment
        elif [[ -f "requirements.txt" ]]; then
            audit_opts+=("-r" "requirements.txt")
        elif [[ -f "Pipfile.lock" ]]; then
            audit_opts+=("-r" "Pipfile.lock")
        fi

        if pip-audit "${audit_opts[@]}"; then
            success "pip-audit passed"
        else
            error "pip-audit found vulnerable dependencies"
            echo ""
            echo "Run '(cd $app_root && pip-audit)' for details"
            echo "Auto-fix with: (cd $app_root && pip-audit --fix)"
            exit 1
        fi
    )
}

# Main
main() {
    local failed=0

    echo ""
    echo "Running Python security checks..."
    echo ""

    # Find app roots from changed Python files
    local app_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && app_roots+=("$root")
    done <<< "$(find_changed_app_roots)"

    if [[ ${#app_roots[@]} -eq 0 ]]; then
        info "No Python app roots with changed files found - skipping security validation"
        return 0
    fi

    # Run security checks per app root
    for app_root in "${app_roots[@]}"; do
        if [[ "$app_root" != "." ]]; then
            echo "App root: $app_root"
            echo ""
        fi

        # Set up virtualenv for tool discovery
        setup_venv "$app_root"

        # Run Bandit
        if [[ "$BANDIT_ENABLED" == "true" ]]; then
            run_bandit "$app_root" || failed=$((failed + 1))
        fi

        # Run pip-audit
        if [[ "$PIP_AUDIT_ENABLED" == "true" ]]; then
            run_pip_audit "$app_root" || failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "Python security validation failed"
        return 1
    fi

    success "Python security validation passed"
    return 0
}

main "$@"
