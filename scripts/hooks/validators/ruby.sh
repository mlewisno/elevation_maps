#!/usr/bin/env bash
#
# ruby.sh - Ruby/Rails validation
#
# Runs:
# - RuboCop on changed Ruby files
# - RSpec on changed spec files or specs for changed source files
#
# Supports monorepos: automatically discovers the nearest Gemfile
# for each changed file and groups validation by app root.
#
# Usage: ruby.sh
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
RUBOCOP_ENABLED=true
RSPEC_ENABLED=true
RSPEC_FAIL_FAST=true

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
    done

    for root in "${roots[@]+"${roots[@]}"}"; do
        echo "$root"
    done
}

# Get changed Ruby files (staged)
get_changed_ruby_files() {
    git diff --cached --name-only --diff-filter=ACM | grep '\.rb$' || true
}

# Find spec file for a source file (must be called from within app root)
find_spec_for() {
    local source_file="$1"
    local basename
    local possible_specs=()

    basename=$(basename "$source_file" .rb)

    # Common spec locations
    possible_specs=(
        "spec/${source_file%%.rb}_spec.rb"
        "spec/models/${basename}_spec.rb"
        "spec/controllers/${basename}_spec.rb"
        "spec/services/${basename}_spec.rb"
        "spec/lib/${basename}_spec.rb"
        "test/${source_file%%.rb}_test.rb"
    )

    for spec in "${possible_specs[@]}"; do
        if [[ -f "$spec" ]]; then
            echo "$spec"
            return 0
        fi
    done

    return 1
}

# Run RuboCop on changed files within an app root
run_rubocop() {
    local app_root="$1"
    shift
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    (
        cd "$app_root"

        if ! bundle show rubocop &> /dev/null; then
            warn "rubocop not in bundle ($app_root) - skipping"
            exit 0
        fi

        info "Running RuboCop on ${#files[@]} file(s)..."

        if bundle exec rubocop --force-exclusion "${files[@]}"; then
            success "RuboCop passed"
        else
            error "RuboCop found issues"
            echo ""
            echo "To auto-fix: (cd $app_root && bundle exec rubocop -a ${files[*]})"
            exit 1
        fi
    )
}

# Run RSpec on relevant specs within an app root
run_rspec() {
    local app_root="$1"
    shift
    local app_files=("$@")

    (
        cd "$app_root"

        local spec_files=()

        for file in "${app_files[@]}"; do
            # If it's already a spec file, include it directly
            if [[ "$file" == *_spec.rb ]]; then
                spec_files+=("$file")
                continue
            fi

            # Otherwise, try to find a matching spec
            local spec
            spec=$(find_spec_for "$file" || true)
            if [[ -n "$spec" ]]; then
                # Deduplicate
                local already=false
                for existing in "${spec_files[@]+"${spec_files[@]}"}"; do
                    if [[ "$existing" == "$spec" ]]; then
                        already=true
                        break
                    fi
                done
                if [[ "$already" == "false" ]]; then
                    spec_files+=("$spec")
                fi
            fi
        done

        if [[ ${#spec_files[@]} -eq 0 ]]; then
            info "No specs to run"
            return 0
        fi

        if ! bundle show rspec-core &> /dev/null && ! bundle show rspec-rails &> /dev/null; then
            warn "rspec not in bundle ($app_root) - skipping"
            return 0
        fi

        info "Running RSpec on ${#spec_files[@]} spec file(s)..."
        for f in "${spec_files[@]}"; do
            echo "  - $f"
        done

        local rspec_opts=""
        if [[ "$RSPEC_FAIL_FAST" == "true" ]]; then
            rspec_opts="--fail-fast"
        fi

        if bundle exec rspec $rspec_opts "${spec_files[@]}"; then
            success "RSpec passed"
        else
            error "RSpec failed"
            exit 1
        fi
    )
}

# Main
main() {
    local failed=0

    # Collect changed Ruby files
    local ruby_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && ruby_files+=("$file")
    done <<< "$(get_changed_ruby_files)"

    if [[ ${#ruby_files[@]} -eq 0 ]]; then
        info "No Ruby files changed"
        return 0
    fi

    # Find unique app roots
    local app_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && app_roots+=("$root")
    done <<< "$(collect_app_roots "${ruby_files[@]}")"

    if [[ ${#app_roots[@]} -eq 0 ]]; then
        warn "No Gemfile found for changed Ruby files - skipping"
        return 0
    fi

    # Run validators per app root
    for app_root in "${app_roots[@]}"; do
        echo ""
        if [[ "$app_root" != "." ]]; then
            echo "App root: $app_root"
        fi

        # Filter files for this app root and convert to app-relative paths
        local app_files=()
        for file in "${ruby_files[@]}"; do
            local file_root
            file_root=$(find_gemfile_dir "$file") || continue
            if [[ "$file_root" == "$app_root" ]]; then
                app_files+=("$(get_app_relative_path "$file" "$app_root")")
            fi
        done

        echo "Ruby files changed: ${#app_files[@]}"
        for f in "${app_files[@]}"; do
            echo "  - $f"
        done
        echo ""

        # Verify bundle is available in app root
        if ! (cd "$app_root" && [[ -f "Gemfile" ]]); then
            warn "No Gemfile in $app_root - skipping"
            continue
        fi

        if ! command -v bundle &> /dev/null; then
            warn "bundler not found - skipping Ruby validation"
            continue
        fi

        # Run RuboCop
        if [[ "$RUBOCOP_ENABLED" == "true" ]]; then
            run_rubocop "$app_root" "${app_files[@]}" || failed=$((failed + 1))
        fi

        # Run RSpec
        if [[ "$RSPEC_ENABLED" == "true" ]]; then
            run_rspec "$app_root" "${app_files[@]}" || failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        error "Ruby validation failed"
        return 1
    fi

    success "Ruby validation passed"
    return 0
}

main "$@"
