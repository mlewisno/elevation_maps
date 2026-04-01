#!/usr/bin/env bash
#
# python.sh - Python project validation
#
# Runs:
# - Ruff (lint + format check) on changed Python files
# - mypy (type checking) on changed Python files
# - pytest on changed test files or tests for changed source files
#
# Supports monorepos: automatically discovers the nearest pyproject.toml,
# setup.py, or requirements.txt for each changed file and groups validation
# by project root.
#
# Usage: python.sh
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
RUFF_ENABLED=true
MYPY_ENABLED=true
PYTEST_ENABLED=true
PYTEST_FAIL_FAST=true

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
# Walks up from the file's directory toward the repo root.
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

    # Fall back to requirements.txt (weaker signal)
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

# Convert a repo-relative path to an app-relative path.
get_app_relative_path() {
    local file="$1"
    local app_root="$2"

    if [[ "$app_root" == "." ]]; then
        echo "$file"
    else
        echo "${file#"$app_root"/}"
    fi
}

# Collect unique app roots from a list of files.
# Prints one app root per line.
collect_app_roots() {
    local files=("$@")
    local roots=()

    for file in "${files[@]}"; do
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
    done

    for root in "${roots[@]+"${roots[@]}"}"; do
        echo "$root"
    done
}

# Get changed Python files (staged)
get_changed_python_files() {
    git diff --cached --name-only --diff-filter=ACM | grep '\.py$' || true
}

# Resolve the python/tool command, preferring venv if available.
# Sets PYTHON_CMD and prepends venv bin to PATH if found.
setup_venv() {
    local app_root="$1"

    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        info "Using active virtualenv: $VIRTUAL_ENV"
        return 0
    fi

    for venv_dir in .venv venv; do
        if [[ -d "$app_root/$venv_dir/bin" ]]; then
            export PATH="$app_root/$venv_dir/bin:$PATH"
            info "Using virtualenv: $venv_dir/"
            return 0
        fi
    done

    return 0
}

# Find test file for a source file (must be called from within app root)
find_test_for() {
    local source_file="$1"
    local basename
    local dir

    basename=$(basename "$source_file" .py)
    dir=$(dirname "$source_file")

    local possible_tests=(
        "tests/test_${basename}.py"
        "tests/${dir}/test_${basename}.py"
        "test/test_${basename}.py"
        "test/${dir}/test_${basename}.py"
        "${dir}/test_${basename}.py"
        "tests/${source_file%%.py}_test.py"
    )

    for test_file in "${possible_tests[@]}"; do
        if [[ -f "$test_file" ]]; then
            echo "$test_file"
            return 0
        fi
    done

    return 1
}

# Run Ruff lint + format check on changed files within an app root
run_ruff() {
    local app_root="$1"
    shift
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    (
        cd "$app_root"

        if ! command -v ruff &> /dev/null; then
            warn "ruff not found ($app_root) - skipping lint/format check"
            warn "Install with: pip install ruff"
            exit 0
        fi

        info "Running Ruff lint on ${#files[@]} file(s)..."

        local lint_failed=false
        if ! ruff check "${files[@]}"; then
            error "Ruff lint found issues"
            echo ""
            echo "To auto-fix: (cd $app_root && ruff check --fix ${files[*]})"
            lint_failed=true
        else
            success "Ruff lint passed"
        fi

        info "Running Ruff format check on ${#files[@]} file(s)..."

        local format_failed=false
        if ! ruff format --check "${files[@]}"; then
            error "Ruff format check failed"
            echo ""
            echo "To auto-fix: (cd $app_root && ruff format ${files[*]})"
            format_failed=true
        else
            success "Ruff format passed"
        fi

        if [[ "$lint_failed" == "true" || "$format_failed" == "true" ]]; then
            exit 1
        fi
    )
}

# Run mypy type checking on changed files within an app root
run_mypy() {
    local app_root="$1"
    shift
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    (
        cd "$app_root"

        if ! command -v mypy &> /dev/null; then
            warn "mypy not found ($app_root) - skipping type checking"
            warn "Install with: pip install mypy"
            exit 0
        fi

        info "Running mypy on ${#files[@]} file(s)..."

        if mypy --follow-imports=skip "${files[@]}"; then
            success "mypy passed"
        else
            error "mypy found type errors"
            echo ""
            echo "Run '(cd $app_root && mypy ${files[*]})' for details"
            exit 1
        fi
    )
}

# Run pytest on relevant test files within an app root
run_pytest() {
    local app_root="$1"
    shift
    local app_files=("$@")

    (
        cd "$app_root"

        local test_files=()

        for file in "${app_files[@]}"; do
            # If it's already a test file, include it directly
            if [[ "$file" == test_*.py || "$file" == **/test_*.py || "$file" == *_test.py ]]; then
                test_files+=("$file")
                continue
            fi

            # Otherwise, try to find a matching test
            local test_file
            test_file=$(find_test_for "$file" || true)
            if [[ -n "$test_file" ]]; then
                # Deduplicate
                local already=false
                for existing in "${test_files[@]+"${test_files[@]}"}"; do
                    if [[ "$existing" == "$test_file" ]]; then
                        already=true
                        break
                    fi
                done
                if [[ "$already" == "false" ]]; then
                    test_files+=("$test_file")
                fi
            fi
        done

        if [[ ${#test_files[@]} -eq 0 ]]; then
            info "No tests to run"
            return 0
        fi

        if ! command -v pytest &> /dev/null; then
            warn "pytest not found ($app_root) - skipping tests"
            warn "Install with: pip install pytest"
            return 0
        fi

        info "Running pytest on ${#test_files[@]} test file(s)..."
        for f in "${test_files[@]}"; do
            echo "  - $f"
        done

        local pytest_opts=""
        if [[ "$PYTEST_FAIL_FAST" == "true" ]]; then
            pytest_opts="-x"
        fi

        if pytest $pytest_opts "${test_files[@]}"; then
            success "pytest passed"
        else
            error "pytest failed"
            exit 1
        fi
    )
}

# Main
main() {
    local failed=0

    # Collect changed Python files
    local python_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && python_files+=("$file")
    done <<< "$(get_changed_python_files)"

    if [[ ${#python_files[@]} -eq 0 ]]; then
        info "No Python files changed"
        return 0
    fi

    # Find unique app roots
    local app_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && app_roots+=("$root")
    done <<< "$(collect_app_roots "${python_files[@]}")"

    if [[ ${#app_roots[@]} -eq 0 ]]; then
        warn "No Python project root found for changed files - skipping"
        return 0
    fi

    # Run validators per app root
    for app_root in "${app_roots[@]}"; do
        echo ""
        if [[ "$app_root" != "." ]]; then
            echo "App root: $app_root"
        fi

        # Set up virtualenv if available
        setup_venv "$app_root"

        # Filter files for this app root and convert to app-relative paths
        local app_files=()
        for file in "${python_files[@]}"; do
            local file_root
            file_root=$(find_python_root "$file") || continue
            if [[ "$file_root" == "$app_root" ]]; then
                app_files+=("$(get_app_relative_path "$file" "$app_root")")
            fi
        done

        echo "Python files changed: ${#app_files[@]}"
        for f in "${app_files[@]}"; do
            echo "  - $f"
        done
        echo ""

        # Run Ruff (lint + format)
        if [[ "$RUFF_ENABLED" == "true" ]]; then
            run_ruff "$app_root" "${app_files[@]}" || failed=$((failed + 1))
        fi

        # Run mypy
        if [[ "$MYPY_ENABLED" == "true" ]]; then
            run_mypy "$app_root" "${app_files[@]}" || failed=$((failed + 1))
        fi

        # Run pytest
        if [[ "$PYTEST_ENABLED" == "true" ]]; then
            run_pytest "$app_root" "${app_files[@]}" || failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "Python validation failed"
        return 1
    fi

    success "Python validation passed"
    return 0
}

main "$@"
