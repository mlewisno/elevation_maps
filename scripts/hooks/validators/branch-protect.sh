#!/usr/bin/env bash
#
# branch-protect.sh - Prevent direct commits to protected branches
#
# Blocks commits to main/master. Use feature branches instead.
#
# Configuration (in config.sh):
#   PROTECTED_BRANCHES - Array of branch names to protect (default: main master)
#
# Usage: branch-protect.sh
# Returns: 0 if not on protected branch, 1 if blocked

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"

# Default protected branches
PROTECTED_BRANCHES=(main master)

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Get current branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [[ -z "$CURRENT_BRANCH" ]]; then
    # Detached HEAD — not a protected branch
    echo -e "${GREEN}OK:${NC} Detached HEAD, not a protected branch"
    exit 0
fi

for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [[ "$CURRENT_BRANCH" == "$branch" ]]; then
        echo -e "${RED}BLOCKED:${NC} Direct commits to '${branch}' are not allowed."
        echo ""
        echo "Create a feature branch instead:"
        echo "  git checkout -b feat-<issue>-<description>"
        echo ""
        echo "Or use /feature to start a tracked feature workflow."
        exit 1
    fi
done

echo -e "${GREEN}OK:${NC} Branch '${CURRENT_BRANCH}' is not protected"
exit 0
