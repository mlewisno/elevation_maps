#!/usr/bin/env bash
#
# readme-check.sh - Check README.md freshness against actual repo structure
#
# Checks:
# - Directories listed in README file tree exist
# - Key directories not in README are flagged
# - Skills table matches actual skills
#
# Usage: readme-check.sh
# Returns: 0 on success, 1 on blocking errors, 2 on warnings only

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Default values
README_CHECK_ENABLED=true
README_CHECK_BLOCKING=false

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Find project root
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/README.md" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "$PWD"
}

PROJECT_ROOT=$(find_project_root)
README="$PROJECT_ROOT/README.md"

ERRORS=()
WARNINGS=()

error() {
    ERRORS+=("$1")
    echo -e "${RED}ERROR:${NC} $1" >&2
}

warn() {
    WARNINGS+=("$1")
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}OK:${NC} $1"
}

info() {
    echo -e "${CYAN}INFO:${NC} $1"
}

# Check that top-level directories mentioned in README exist
check_tree_entries() {
    if [[ ! -f "$README" ]]; then
        warn "No README.md found"
        return
    fi

    # Extract directory/file entries from the tree block
    # Look for lines like "├── dirname/" or "│   ├── filename"
    local tree_entries
    tree_entries=$(grep -E '(├──|└──)' "$README" | \
        sed -E 's/.*[├└]── //' | \
        sed -E 's/[[:space:]]+#.*//' | \
        sed 's/[[:space:]]*$//' || true)

    if [[ -z "$tree_entries" ]]; then
        warn "No file tree found in README.md"
        return
    fi

    local missing=()

    while IFS= read -r entry; do
        # Skip empty lines
        [[ -z "$entry" ]] && continue

        # Strip trailing slash for directories
        local clean_entry="${entry%/}"

        # Check if file/dir exists anywhere in the project
        local found
        found=$(find "$PROJECT_ROOT" -name "$clean_entry" -maxdepth 5 2>/dev/null | head -1)
        if [[ -z "$found" ]]; then
            missing+=("$entry")
        fi
    done <<< "$tree_entries"

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "README tree references items that don't exist:"
        for item in "${missing[@]}"; do
            echo "    - $item"
        done
    else
        success "All README tree entries exist"
    fi
}

# Check for key directories/files missing from README
check_missing_from_readme() {
    if [[ ! -f "$README" ]]; then
        return
    fi

    local readme_content
    readme_content=$(cat "$README")

    # Top-level directories that should be mentioned
    local key_dirs=()
    for dir in "$PROJECT_ROOT"/*/; do
        [[ -d "$dir" ]] || continue
        local dirname
        dirname=$(basename "$dir")
        # Skip hidden dirs and common ignore patterns
        [[ "$dirname" == .* ]] && continue
        [[ "$dirname" == node_modules ]] && continue
        [[ "$dirname" == vendor ]] && continue
        key_dirs+=("$dirname")
    done

    local missing=()
    for dir in "${key_dirs[@]}"; do
        if ! echo "$readme_content" | grep -q "$dir"; then
            missing+=("$dir/")
        fi
    done

    # Check .claude subdirectories
    if [[ -d "$PROJECT_ROOT/.claude" ]]; then
        for dir in "$PROJECT_ROOT/.claude"/*/; do
            [[ -d "$dir" ]] || continue
            local dirname
            dirname=$(basename "$dir")
            if ! echo "$readme_content" | grep -q "$dirname"; then
                missing+=(".claude/$dirname/")
            fi
        done
    fi

    # Check .specs if it exists
    if [[ -d "$PROJECT_ROOT/.specs" ]] && ! echo "$readme_content" | grep -q "\.specs"; then
        missing+=(".specs/")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Directories exist but aren't mentioned in README:"
        for item in "${missing[@]}"; do
            echo "    - $item"
        done
    else
        success "All key directories are mentioned in README"
    fi
}

# Check skills table matches actual skills
check_skills_table() {
    local skills_dir="$PROJECT_ROOT/.claude/skills"

    if [[ ! -d "$skills_dir" ]]; then
        return
    fi

    if [[ ! -f "$README" ]]; then
        return
    fi

    local readme_content
    readme_content=$(cat "$README")

    # Get actual skills (directories with SKILL.md)
    local actual_skills=()
    for skill_dir in "$skills_dir"/*/; do
        [[ -d "$skill_dir" ]] || continue
        if [[ -f "$skill_dir/SKILL.md" ]]; then
            actual_skills+=("$(basename "$skill_dir")")
        fi
    done

    # Check which actual skills are missing from README
    local missing_skills=()
    for skill in "${actual_skills[@]}"; do
        if ! echo "$readme_content" | grep -q "$skill"; then
            missing_skills+=("$skill")
        fi
    done

    # Check which README skills don't exist
    local readme_skills
    readme_skills=$(echo "$readme_content" | \
        grep -E '^\| .+ \| `/' | \
        sed -E 's/.*`\/([^`]+)`.*/\1/' || true)

    local stale_skills=()
    if [[ -n "$readme_skills" ]]; then
        while IFS= read -r skill; do
            [[ -z "$skill" ]] && continue
            if [[ ! -d "$skills_dir/$skill" ]]; then
                stale_skills+=("$skill")
            fi
        done <<< "$readme_skills"
    fi

    if [[ ${#missing_skills[@]} -gt 0 ]]; then
        warn "Skills exist but aren't in README table:"
        for skill in "${missing_skills[@]}"; do
            echo "    - /$skill"
        done
    fi

    if [[ ${#stale_skills[@]} -gt 0 ]]; then
        warn "README lists skills that don't exist:"
        for skill in "${stale_skills[@]}"; do
            echo "    - /$skill"
        done
    fi

    if [[ ${#missing_skills[@]} -eq 0 ]] && [[ ${#stale_skills[@]} -eq 0 ]]; then
        success "Skills table matches actual skills"
    fi
}

# Check README was updated recently relative to structural changes
check_readme_staleness() {
    if [[ ! -f "$README" ]]; then
        return
    fi

    # Get last README modification commit
    local readme_last_modified
    readme_last_modified=$(git log -1 --format="%H" -- README.md 2>/dev/null || true)

    if [[ -z "$readme_last_modified" ]]; then
        warn "README.md has never been committed"
        return
    fi

    # Check if structural files have been added since README was last updated
    local structural_changes
    structural_changes=$(git log --name-only --diff-filter=A --format="" \
        "$readme_last_modified"..HEAD -- \
        '.claude/skills/*/SKILL.md' \
        '.claude/rules/*.md' \
        '.claude/rules/*/*.md' \
        'scripts/*.sh' \
        'scripts/hooks/validators/*.sh' \
        2>/dev/null | sort -u | grep -v '^$' || true)

    if [[ -n "$structural_changes" ]]; then
        warn "Structural files added since README was last updated:"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            echo "    - $file"
        done <<< "$structural_changes"
        echo ""
        echo "  Consider updating README.md to reflect these additions."
    else
        success "No structural changes since last README update"
    fi
}

# Main logic
main() {
    if [[ "$README_CHECK_ENABLED" != "true" ]]; then
        info "README check is disabled"
        return 0
    fi

    echo ""
    echo "README freshness check:"
    echo ""

    check_tree_entries
    check_missing_from_readme
    check_skills_table
    check_readme_staleness

    echo ""

    # Summary
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}Found ${#ERRORS[@]} error(s)${NC}"
        if [[ "$README_CHECK_BLOCKING" == "true" ]]; then
            return 1
        fi
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Found ${#WARNINGS[@]} warning(s)${NC}"
        echo -e "  Run: ${CYAN}git diff README.md${NC} after updating to verify"
        if [[ ${#ERRORS[@]} -eq 0 ]]; then
            return 2  # Warnings only
        fi
    fi

    if [[ ${#ERRORS[@]} -eq 0 ]] && [[ ${#WARNINGS[@]} -eq 0 ]]; then
        success "README is up to date"
    fi

    return 0
}

main "$@"
