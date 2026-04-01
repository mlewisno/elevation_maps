#!/usr/bin/env bash
#
# context-bloat.sh - Detect context window bloat in Claude Code configuration
#
# Checks:
# - Large skill files (>500 lines by default)
# - Large rule files
# - Deeply nested directory structures
# - Excessive code examples
# - Duplicate content across files
#
# Usage: context-bloat.sh [directory]
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
CONTEXT_BLOAT_ENABLED=true
CONTEXT_BLOAT_BLOCKING=false
SKILL_LINE_LIMIT=500
RULE_LINE_LIMIT=300
MAX_NESTING_DEPTH=3
MAX_CODE_BLOCK_LINES=50
CODE_BLOCK_WARN_THRESHOLD=5  # Warn if >5 large code blocks

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

# Find project root
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.claude" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    echo "$PWD"
}

PROJECT_ROOT=$(find_project_root)

# Check file sizes
check_file_sizes() {
    local claude_dir="$PROJECT_ROOT/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        return 0
    fi

    echo "Checking file sizes..."
    echo ""

    local large_files=()

    # Check skill files
    while IFS= read -r file; do
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        local relative_path="${file#$PROJECT_ROOT/}"

        if [[ "$lines" -gt "$SKILL_LINE_LIMIT" ]]; then
            large_files+=("$relative_path: $lines lines (limit: $SKILL_LINE_LIMIT)")
        elif [[ "$lines" -gt $((SKILL_LINE_LIMIT * 3 / 4)) ]]; then
            info "$relative_path: $lines lines (approaching limit of $SKILL_LINE_LIMIT)"
        fi
    done < <(find "$claude_dir/skills" -name "*.md" -type f 2>/dev/null || true)

    # Check rule files
    while IFS= read -r file; do
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        local relative_path="${file#$PROJECT_ROOT/}"

        if [[ "$lines" -gt "$RULE_LINE_LIMIT" ]]; then
            large_files+=("$relative_path: $lines lines (limit: $RULE_LINE_LIMIT)")
        elif [[ "$lines" -gt $((RULE_LINE_LIMIT * 3 / 4)) ]]; then
            info "$relative_path: $lines lines (approaching limit of $RULE_LINE_LIMIT)"
        fi
    done < <(find "$claude_dir/rules" -name "*.md" -type f 2>/dev/null || true)

    if [[ ${#large_files[@]} -gt 0 ]]; then
        warn "Large files detected (impacts context window):"
        for entry in "${large_files[@]}"; do
            echo "    - $entry"
        done
        echo ""
        echo "  Consider:"
        echo "    - Splitting into multiple focused files"
        echo "    - Moving examples to separate files"
        echo "    - Using links instead of inline content"
    else
        success "All files within size limits"
    fi
}

# Check directory nesting depth
check_nesting_depth() {
    local claude_dir="$PROJECT_ROOT/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        return 0
    fi

    echo ""
    echo "Checking directory nesting..."
    echo ""

    local deep_paths=()

    while IFS= read -r dir; do
        # Skip the root .claude directory itself
        [[ "$dir" == "$claude_dir" ]] && continue

        # Count depth relative to .claude
        local relative="${dir#$claude_dir/}"

        # Skip empty relative paths
        [[ -z "$relative" ]] && continue

        local depth
        depth=$(echo "$relative" | tr '/' '\n' | grep -c .)

        if [[ "$depth" -gt "$MAX_NESTING_DEPTH" ]]; then
            deep_paths+=("$relative (depth: $depth)")
        fi
    done < <(find "$claude_dir" -type d 2>/dev/null || true)

    if [[ ${#deep_paths[@]} -gt 0 ]]; then
        warn "Deeply nested directories (may complicate navigation):"
        for path in "${deep_paths[@]}"; do
            echo "    - $path"
        done
        echo ""
        echo "  Consider flattening directory structure"
    else
        success "Directory nesting within limits (max: $MAX_NESTING_DEPTH)"
    fi
}

# Check for excessive code examples
check_code_blocks() {
    local claude_dir="$PROJECT_ROOT/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        return 0
    fi

    echo ""
    echo "Checking code block sizes..."
    echo ""

    local files_with_large_blocks=()

    while IFS= read -r file; do
        local relative_path="${file#$PROJECT_ROOT/}"
        local in_code_block=false
        local block_lines=0
        local large_blocks=0
        local line_num=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            line_num=$((line_num + 1))

            if [[ "$line" =~ ^\`\`\` ]]; then
                if [[ "$in_code_block" == true ]]; then
                    # End of block
                    if [[ "$block_lines" -gt "$MAX_CODE_BLOCK_LINES" ]]; then
                        large_blocks=$((large_blocks + 1))
                    fi
                    in_code_block=false
                    block_lines=0
                else
                    in_code_block=true
                    block_lines=0
                fi
            elif [[ "$in_code_block" == true ]]; then
                block_lines=$((block_lines + 1))
            fi
        done < "$file"

        if [[ "$large_blocks" -gt "$CODE_BLOCK_WARN_THRESHOLD" ]]; then
            files_with_large_blocks+=("$relative_path: $large_blocks large code blocks (>$MAX_CODE_BLOCK_LINES lines each)")
        fi
    done < <(find "$claude_dir" -name "*.md" -type f 2>/dev/null || true)

    if [[ ${#files_with_large_blocks[@]} -gt 0 ]]; then
        warn "Files with many large code blocks:"
        for entry in "${files_with_large_blocks[@]}"; do
            echo "    - $entry"
        done
        echo ""
        echo "  Consider:"
        echo "    - Moving large examples to separate files"
        echo "    - Using shorter, focused examples"
        echo "    - Linking to external documentation"
    else
        success "Code blocks within reasonable sizes"
    fi
}

# Check for potential duplicate content
check_duplicates() {
    local claude_dir="$PROJECT_ROOT/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        return 0
    fi

    echo ""
    echo "Checking for potential duplicate patterns..."
    echo ""

    # Look for common headings that appear in multiple files
    local heading_files
    heading_files=$(mktemp)

    # Find all level-2 headings
    grep -rh '^## ' "$claude_dir" 2>/dev/null | \
        sort | uniq -c | sort -rn | head -10 > "$heading_files" || true

    # Check for headings that appear in many files
    local duplicate_headings=()
    while IFS= read -r line; do
        local count
        count=$(echo "$line" | awk '{print $1}')
        local heading
        heading=$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')

        if [[ "$count" -gt 3 ]]; then
            duplicate_headings+=("'$heading' appears in $count files")
        fi
    done < "$heading_files"

    rm -f "$heading_files"

    if [[ ${#duplicate_headings[@]} -gt 0 ]]; then
        info "Common patterns across files (may indicate opportunities to consolidate):"
        for entry in "${duplicate_headings[@]}"; do
            echo "    - $entry"
        done
        echo ""
        echo "  This is informational - some repetition is expected."
        echo "  Consider consolidating if content is truly duplicated."
    fi
}

# Check total context size
check_total_size() {
    local claude_dir="$PROJECT_ROOT/.claude"

    if [[ ! -d "$claude_dir" ]]; then
        return 0
    fi

    echo ""
    echo "Context size summary..."
    echo ""

    # Count total lines and files
    local total_lines=0
    local file_count=0

    while IFS= read -r file; do
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        total_lines=$((total_lines + lines))
        file_count=$((file_count + 1))
    done < <(find "$claude_dir" -name "*.md" -type f 2>/dev/null || true)

    # Estimate tokens (rough: ~4 chars per token, ~80 chars per line)
    local estimated_tokens=$((total_lines * 20))

    echo "  Files: $file_count"
    echo "  Total lines: $total_lines"
    echo "  Estimated tokens: ~$estimated_tokens"
    echo ""

    # Warn if getting large
    if [[ "$estimated_tokens" -gt 50000 ]]; then
        warn "Context is getting large (~$estimated_tokens tokens)"
        echo "  This may impact:"
        echo "    - Response quality (less room for reasoning)"
        echo "    - Latency (more to process)"
        echo "    - Cost (more tokens = more cost)"
        echo ""
        echo "  Consider auditing for unnecessary content"
    elif [[ "$estimated_tokens" -gt 30000 ]]; then
        info "Context is moderate (~$estimated_tokens tokens)"
    else
        success "Context size is reasonable (~$estimated_tokens tokens)"
    fi
}

# Main logic
main() {
    if [[ "$CONTEXT_BLOAT_ENABLED" != "true" ]]; then
        info "Context bloat check is disabled"
        return 0
    fi

    local target="${1:-$PROJECT_ROOT}"

    echo ""
    echo "Context bloat analysis:"
    echo ""

    check_file_sizes
    check_nesting_depth
    check_code_blocks
    check_duplicates
    check_total_size

    echo ""

    # Summary
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}Found ${#ERRORS[@]} error(s)${NC}"
        if [[ "$CONTEXT_BLOAT_BLOCKING" == "true" ]]; then
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
        success "All context bloat checks passed"
    fi

    return 0
}

main "$@"
