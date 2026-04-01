#!/usr/bin/env bash
#
# rails-frontend.sh - Rails JavaScript/CSS validation
#
# Runs:
# - ESLint on changed JavaScript/TypeScript files
# - Stylelint on changed CSS/SCSS files
#
# Supports monorepos: automatically discovers the nearest package.json
# for each changed file and groups validation by app root.
#
# Usage: frontend.sh
# Returns: 0 on success, 1 on failure, 2 on warnings only

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
ESLINT_ENABLED=true
STYLELINT_ENABLED=true
ESLINT_AUTOFIX=false
STYLELINT_AUTOFIX=false

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

# Find nearest ancestor directory containing a package.json.
# Walks up from the file's directory toward the repo root.
find_package_json_dir() {
    local file="$1"
    local dir
    dir=$(dirname "$file")

    while [[ "$dir" != "." && "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    # Check repo root
    if [[ -f "package.json" ]]; then
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
        root=$(find_package_json_dir "$file") || continue

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

# Detect which package manager is available in the given directory
detect_package_manager() {
    local app_root="$1"

    if [[ -f "$app_root/bun.lockb" ]] || [[ -f "$app_root/bun.lock" ]]; then
        if command -v bun &> /dev/null; then
            echo "bun"
            return 0
        fi
    fi

    if [[ -f "$app_root/yarn.lock" ]]; then
        if command -v yarn &> /dev/null; then
            echo "yarn"
            return 0
        fi
    fi

    if [[ -f "$app_root/pnpm-lock.yaml" ]]; then
        if command -v pnpm &> /dev/null; then
            echo "pnpm"
            return 0
        fi
    fi

    if command -v npx &> /dev/null; then
        echo "npx"
        return 0
    fi

    return 1
}

# Build the runner command prefix based on package manager
# e.g., "npx", "yarn", "bunx", "pnpm exec"
get_runner() {
    local pkg_manager="$1"

    case "$pkg_manager" in
        bun)  echo "bunx" ;;
        yarn) echo "yarn" ;;
        pnpm) echo "pnpm exec" ;;
        npx)  echo "npx" ;;
        *)    echo "npx" ;;
    esac
}

# Get changed JS/TS files (staged)
get_changed_js_files() {
    git diff --cached --name-only --diff-filter=ACM | grep -E '\.(js|mjs|cjs|jsx|ts|tsx)$' || true
}

# Get changed CSS/SCSS files (staged)
get_changed_css_files() {
    git diff --cached --name-only --diff-filter=ACM | grep -E '\.(css|scss|sass)$' || true
}

# Check if a tool is available via the package manager in the given app root
tool_available() {
    local app_root="$1"
    local tool="$2"
    local runner="$3"

    (
        cd "$app_root"

        # Check if tool is in devDependencies or dependencies
        if [[ -f "package.json" ]]; then
            if grep -q "\"$tool\"" package.json 2>/dev/null; then
                return 0
            fi
        fi

        # Check node_modules/.bin as fallback
        if [[ -x "node_modules/.bin/$tool" ]]; then
            return 0
        fi

        return 1
    )
}

# Run ESLint on changed files within an app root
run_eslint() {
    local app_root="$1"
    local runner="$2"
    shift 2
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    (
        cd "$app_root"

        if ! tool_available "." "eslint" "$runner"; then
            warn "eslint not found in $app_root - skipping"
            exit 0
        fi

        info "Running ESLint on ${#files[@]} file(s)..."

        local eslint_opts=()
        if [[ "$ESLINT_AUTOFIX" == "true" ]]; then
            eslint_opts+=(--fix)
        fi

        if $runner eslint "${eslint_opts[@]+"${eslint_opts[@]}"}" "${files[@]}"; then
            success "ESLint passed"
        else
            error "ESLint found issues"
            echo ""
            echo "To auto-fix: (cd $app_root && $runner eslint --fix ${files[*]})"
            exit 1
        fi
    )
}

# Run Stylelint on changed files within an app root
run_stylelint() {
    local app_root="$1"
    local runner="$2"
    shift 2
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    (
        cd "$app_root"

        if ! tool_available "." "stylelint" "$runner"; then
            warn "stylelint not found in $app_root - skipping"
            exit 0
        fi

        info "Running Stylelint on ${#files[@]} file(s)..."

        local stylelint_opts=()
        if [[ "$STYLELINT_AUTOFIX" == "true" ]]; then
            stylelint_opts+=(--fix)
        fi

        if $runner stylelint "${stylelint_opts[@]+"${stylelint_opts[@]}"}" "${files[@]}"; then
            success "Stylelint passed"
        else
            error "Stylelint found issues"
            echo ""
            echo "To auto-fix: (cd $app_root && $runner stylelint --fix ${files[*]})"
            exit 1
        fi
    )
}

# Main
main() {
    local failed=0
    local has_files=false

    # Collect changed JS/TS files
    local js_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && js_files+=("$file")
    done <<< "$(get_changed_js_files)"

    # Collect changed CSS/SCSS files
    local css_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && css_files+=("$file")
    done <<< "$(get_changed_css_files)"

    # Combine all frontend files for app root discovery
    local all_files=()
    all_files+=("${js_files[@]+"${js_files[@]}"}")
    all_files+=("${css_files[@]+"${css_files[@]}"}")

    if [[ ${#all_files[@]} -eq 0 ]]; then
        info "No frontend files changed"
        return 0
    fi

    has_files=true

    # Find unique app roots
    local app_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && app_roots+=("$root")
    done <<< "$(collect_app_roots "${all_files[@]}")"

    if [[ ${#app_roots[@]} -eq 0 ]]; then
        warn "No package.json found for changed frontend files - skipping"
        return 0
    fi

    # Run validators per app root
    for app_root in "${app_roots[@]}"; do
        echo ""
        if [[ "$app_root" != "." ]]; then
            echo "App root: $app_root"
        fi

        # Detect package manager
        local pkg_manager
        pkg_manager=$(detect_package_manager "$app_root") || {
            warn "No package manager found in $app_root - skipping"
            continue
        }
        local runner
        runner=$(get_runner "$pkg_manager")

        info "Using package manager: $pkg_manager"

        # Filter JS files for this app root
        local app_js_files=()
        for file in "${js_files[@]+"${js_files[@]}"}"; do
            local file_root
            file_root=$(find_package_json_dir "$file") || continue
            if [[ "$file_root" == "$app_root" ]]; then
                app_js_files+=("$(get_app_relative_path "$file" "$app_root")")
            fi
        done

        # Filter CSS files for this app root
        local app_css_files=()
        for file in "${css_files[@]+"${css_files[@]}"}"; do
            local file_root
            file_root=$(find_package_json_dir "$file") || continue
            if [[ "$file_root" == "$app_root" ]]; then
                app_css_files+=("$(get_app_relative_path "$file" "$app_root")")
            fi
        done

        # Report what we found
        if [[ ${#app_js_files[@]} -gt 0 ]]; then
            echo "JS/TS files changed: ${#app_js_files[@]}"
            for f in "${app_js_files[@]}"; do
                echo "  - $f"
            done
        fi
        if [[ ${#app_css_files[@]} -gt 0 ]]; then
            echo "CSS/SCSS files changed: ${#app_css_files[@]}"
            for f in "${app_css_files[@]}"; do
                echo "  - $f"
            done
        fi
        echo ""

        # Run ESLint on JS/TS files
        if [[ "$ESLINT_ENABLED" == "true" && ${#app_js_files[@]} -gt 0 ]]; then
            run_eslint "$app_root" "$runner" "${app_js_files[@]}" || failed=$((failed + 1))
        fi

        # Run Stylelint on CSS/SCSS files
        if [[ "$STYLELINT_ENABLED" == "true" && ${#app_css_files[@]} -gt 0 ]]; then
            run_stylelint "$app_root" "$runner" "${app_css_files[@]}" || failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "Frontend validation failed"
        return 1
    fi

    if [[ "$has_files" == "true" ]]; then
        success "Frontend validation passed"
    fi
    return 0
}

main "$@"
