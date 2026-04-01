#!/usr/bin/env bash
#
# skill-lint.sh - Validate skill files for determinism and quality
#
# Checks:
# - Valid YAML frontmatter structure
# - Complex inline shell commands that should be extracted to scripts
# - Non-deterministic patterns (date/time, random, network without handling)
# - Required sections present
# - Consistent formatting
#
# Usage: skill-lint.sh [skill-file|directory]
# Returns: 0 on success, 1 on blocking errors, 2 on warnings only

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

# Default values
SKILL_LINT_ENABLED=true
SKILL_MAX_INLINE_COMMANDS=3
SKILL_MAX_COMMAND_LENGTH=80
SKILL_BLOCKING=false

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Counters
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

# Check YAML frontmatter structure
check_frontmatter() {
    local file="$1"
    # Check for frontmatter delimiters
    # Read first line directly to avoid broken pipe from echo|head on large files
    local first_line
    first_line=$(head -1 "$file")
    if [[ "$first_line" != "---" ]]; then
        error "$file: Missing YAML frontmatter (no opening ---)"
        return 1
    fi

    # Find closing delimiter (search from line 2 onward)
    local end_line
    end_line=$(tail -n +2 "$file" | grep -n '^---$' | head -1 | cut -d: -f1)

    if [[ -z "$end_line" ]]; then
        error "$file: Missing closing --- in frontmatter"
        return 1
    fi

    # Extract frontmatter (lines 2 through closing ---)
    local frontmatter_end=$((end_line))
    local frontmatter
    frontmatter=$(sed -n "2,${frontmatter_end}p" "$file")

    # Check required fields
    if ! echo "$frontmatter" | grep -q '^name:'; then
        error "$file: Missing 'name' field in frontmatter"
    fi

    if ! echo "$frontmatter" | grep -q '^description:'; then
        error "$file: Missing 'description' field in frontmatter"
    fi

    if ! echo "$frontmatter" | grep -q '^allowed-tools:'; then
        warn "$file: Missing 'allowed-tools' field in frontmatter"
    fi
}

# Check for complex inline shell commands
check_inline_commands() {
    local file="$1"
    local in_code_block=false
    local code_block_lang=""
    local line_num=0
    local complex_commands=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Track code block state
        if [[ "$line" =~ ^\`\`\`(.*)$ ]]; then
            if [[ "$in_code_block" == false ]]; then
                in_code_block=true
                code_block_lang="${BASH_REMATCH[1]}"
            else
                in_code_block=false
                code_block_lang=""
            fi
            continue
        fi

        # Only check bash/shell code blocks
        if [[ "$in_code_block" == true ]] && [[ "$code_block_lang" =~ ^(bash|sh|shell)?$ ]]; then
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// /}" ]] && continue

            # Check for complex patterns that should be extracted

            # Long command lines
            if [[ ${#line} -gt $SKILL_MAX_COMMAND_LENGTH ]] && [[ ! "$line" =~ ^\# ]]; then
                complex_commands+=("Line $line_num: Command exceeds $SKILL_MAX_COMMAND_LENGTH chars (${#line})")
            fi

            # Multiple pipes (complex pipelines)
            local pipe_count
            pipe_count=$(echo "$line" | tr -cd '|' | wc -c | tr -d ' ')
            if [[ "$pipe_count" -gt 2 ]]; then
                complex_commands+=("Line $line_num: Complex pipeline with $pipe_count pipes - consider extracting to script")
            fi

            # Subshells with complex logic
            if [[ "$line" =~ \$\(.*\&\&.*\) ]] || [[ "$line" =~ \$\(.*\|\|.*\) ]]; then
                complex_commands+=("Line $line_num: Complex subshell with && or || - consider extracting")
            fi

            # Long awk/sed commands
            if [[ "$line" =~ awk[[:space:]]+\'.{40,}\' ]] || [[ "$line" =~ sed[[:space:]]+\'.{40,}\' ]]; then
                complex_commands+=("Line $line_num: Long awk/sed command - consider extracting to script")
            fi
        fi
    done < "$file"

    if [[ ${#complex_commands[@]} -gt $SKILL_MAX_INLINE_COMMANDS ]]; then
        warn "$file: Found ${#complex_commands[@]} complex inline commands (threshold: $SKILL_MAX_INLINE_COMMANDS)"
        for cmd in "${complex_commands[@]}"; do
            echo "    - $cmd"
        done
        echo ""
        echo "  Consider extracting complex shell logic to scripts/skill-helpers/"
        echo "  This improves:"
        echo "    - Testability (scripts can be tested independently)"
        echo "    - Readability (skill focuses on workflow, not implementation)"
        echo "    - Determinism (scripts are versioned and stable)"
    fi
}

# Check for non-deterministic patterns
check_nondeterminism() {
    local file="$1"
    local issues=()

    # Date/time without explanation
    if grep -qE '\$\(date|\`date\`|Date\.now|Time\.now|datetime\.now' "$file"; then
        if ! grep -qi 'timestamp\|log\|audit\|created_at' "$file"; then
            issues+=("Uses date/time commands - ensure this is intentional and documented")
        fi
    fi

    # Random values
    if grep -qE '\$RANDOM|Math\.random|random\.|uuid\.' "$file"; then
        issues+=("Uses random/UUID generation - ensure determinism isn't required")
    fi

    # Network calls without error handling context
    if grep -qE 'curl|wget|fetch\(|http\.' "$file"; then
        if ! grep -qiE 'error|fail|retry|timeout' "$file"; then
            issues+=("Network calls detected - consider documenting error handling")
        fi
    fi

    # Environment-dependent paths
    if grep -qE '~/|/home/|/Users/' "$file"; then
        issues+=("Hardcoded home directory paths - use \$HOME or relative paths")
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            warn "$file: $issue"
        done
    fi
}

# Check required sections
check_sections() {
    local file="$1"
    local required_sections=(
        "^# "  # Main heading (level-1 markdown header)
        "^## Usage"                   # How to use
    )

    local recommended_sections=(
        "^## Process|^## Workflow"
        "^## Output|^## Output Format"
        "^## Error|^## Error Handling"
    )

    for pattern in "${required_sections[@]}"; do
        if ! grep -qE "$pattern" "$file"; then
            error "$file: Missing required section matching: $pattern"
        fi
    done

    for pattern in "${recommended_sections[@]}"; do
        if ! grep -qE "$pattern" "$file"; then
            warn "$file: Consider adding section matching: $pattern"
        fi
    done
}

# Check a single skill file
check_skill() {
    local file="$1"

    info "Checking $file..."

    check_frontmatter "$file"
    check_inline_commands "$file"
    check_nondeterminism "$file"
    check_sections "$file"
}

# Find and check all skill files
check_all_skills() {
    local dir="${1:-.claude/skills}"

    if [[ ! -d "$dir" ]]; then
        info "Skills directory not found: $dir"
        return 0
    fi

    local skill_files
    skill_files=$(find "$dir" -name "SKILL.md" -type f 2>/dev/null)

    if [[ -z "$skill_files" ]]; then
        info "No skill files found in $dir"
        return 0
    fi

    echo ""
    echo "Skill lint analysis:"
    echo ""

    while IFS= read -r file; do
        check_skill "$file"
        echo ""
    done <<< "$skill_files"
}

# Main logic
main() {
    if [[ "$SKILL_LINT_ENABLED" != "true" ]]; then
        info "Skill lint is disabled"
        return 0
    fi

    local target="${1:-}"

    if [[ -n "$target" ]]; then
        if [[ -f "$target" ]]; then
            check_skill "$target"
        elif [[ -d "$target" ]]; then
            check_all_skills "$target"
        else
            error "Not found: $target"
            return 1
        fi
    else
        # Check only changed skill files in staged changes
        local changed_skills
        changed_skills=$(git diff --cached --name-only 2>/dev/null | grep -E '\.claude/skills/.*/SKILL\.md$' || true)

        if [[ -z "$changed_skills" ]]; then
            info "No skill files in staged changes"
            return 0
        fi

        echo ""
        echo "Skill lint analysis (staged files):"
        echo ""

        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                check_skill "$file"
                echo ""
            fi
        done <<< "$changed_skills"
    fi

    # Summary
    echo ""
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}Found ${#ERRORS[@]} error(s)${NC}"
        if [[ "$SKILL_BLOCKING" == "true" ]]; then
            return 1
        fi
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Found ${#WARNINGS[@]} warning(s)${NC}"
        if [[ ${#ERRORS[@]} -eq 0 ]]; then
            return 2  # Warnings only
        fi
    fi

    if [[ ${#ERRORS[@]} -eq 0 ]] && [[ ${#WARNINGS[@]} -eq 0 ]]; then
        success "All skill checks passed"
    fi

    return 0
}

main "$@"
