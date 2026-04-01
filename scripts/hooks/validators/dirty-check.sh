#!/usr/bin/env bash
#
# dirty-check.sh - Pre-push validator for uncommitted changes
#
# Advisory only: warns but never blocks a push.
#
# Exit codes:
#   0 - Repo is clean (or override active)
#   2 - Dirty state detected (warning, non-blocking)
#
# Override: ALLOW_DIRTY=1 env var + [dirty-ok] tag in latest commit
# Config:   DIRTY_CHECK_ENABLED=true in config.sh

set -euo pipefail

# Colors
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Find hooks directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$HOOKS_DIR/lib"
CONFIG_FILE="$HOOKS_DIR/config.sh"

# Load config
DIRTY_CHECK_ENABLED="${DIRTY_CHECK_ENABLED:-true}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Check if enabled
if [[ "$DIRTY_CHECK_ENABLED" != "true" ]]; then
    exit 0
fi

# Check env var override
if [[ "${ALLOW_DIRTY:-}" == "1" ]]; then
    echo -e "${CYAN}Dirty check skipped (ALLOW_DIRTY=1)${NC}"
    exit 0
fi

# Check commit tag override
LATEST_SUBJECT=$(git log -1 --format='%s' 2>/dev/null || echo "")
if [[ "$LATEST_SUBJECT" == *"[dirty-ok]"* ]]; then
    echo -e "${CYAN}Dirty check skipped ([dirty-ok] tag)${NC}"
    exit 0
fi

# Source the shared library
if [[ ! -f "$LIB_DIR/repo-state.sh" ]]; then
    echo -e "${YELLOW}Warning: repo-state.sh not found, skipping dirty check${NC}"
    exit 0
fi
# shellcheck source=/dev/null
source "$LIB_DIR/repo-state.sh"

# Check for dirty state
if ! has_dirty_state; then
    echo -e "${GREEN}Working tree is clean.${NC}"
    exit 0
fi

# Dirty state found — report it
modified=$(get_modified_files)
staged=$(get_staged_files)
untracked=$(get_untracked_files)

echo -e "${YELLOW}Warning: Uncommitted changes detected.${NC}"
echo ""

if [[ -n "$modified" ]]; then
    echo "  Modified (unstaged):"
    echo "$modified" | while read -r f; do echo "    $f"; done
    echo ""
fi

if [[ -n "$staged" ]]; then
    echo "  Staged (not committed):"
    echo "$staged" | while read -r f; do echo "    $f"; done
    echo ""
fi

if [[ -n "$untracked" ]]; then
    local_count=$(_count_lines "$untracked")
    echo "  Untracked ($local_count files):"
    echo "$untracked" | head -10 | while read -r f; do echo "    $f"; done
    if [[ "$local_count" -gt 10 ]]; then
        echo "    ... and $((local_count - 10)) more"
    fi
    echo ""
fi

echo "  Suggested actions:"
echo "    git add -p && git commit    # Stage and commit changes"
echo "    git stash                   # Stash for later"
echo "    ALLOW_DIRTY=1 git push      # Push anyway (add [dirty-ok] to commit)"
echo ""

# Exit 2 = warning (non-blocking)
exit 2
