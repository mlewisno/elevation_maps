#!/usr/bin/env bash
#
# visual-regression.sh — SSIM-based visual regression check
#
# Compares generated 2D renders against reference images.
# Only runs when pipeline-relevant files have changed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Defaults
VISUAL_REGRESSION_ENABLED="${VISUAL_REGRESSION_ENABLED:-true}"
VISUAL_REGRESSION_BLOCKING="${VISUAL_REGRESSION_BLOCKING:-false}"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

if [[ "$VISUAL_REGRESSION_ENABLED" != "true" ]]; then
    exit 0
fi

# Check if pipeline-relevant files changed
PIPELINE_PATTERNS="topo2laser/contours/ topo2laser/svg/ topo2laser/elevation/ topo2laser/render/"
changed_files=$(git diff --name-only origin/main...HEAD 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || echo "")

relevant=false
for pattern in $PIPELINE_PATTERNS; do
    if echo "$changed_files" | grep -q "^$pattern"; then
        relevant=true
        break
    fi
done

if [[ "$relevant" != "true" ]]; then
    echo -e "\033[0;36mINFO:\033[0m No pipeline files changed — skipping visual regression"
    exit 0
fi

echo "Running visual regression check..."

# Find Python in venv or PATH
if [[ -d "$PROJECT_ROOT/.venv/bin" ]]; then
    PYTHON="$PROJECT_ROOT/.venv/bin/python"
elif command -v uv &>/dev/null; then
    PYTHON="uv run python"
else
    PYTHON="python3"
fi

# Run comparison
output=$($PYTHON "$PROJECT_ROOT/scripts/visual-regression-check.py" --all 2>/dev/null) || true
exit_code=$?

if [[ -z "$output" ]]; then
    echo -e "\033[0;33mWARNING:\033[0m Could not run visual regression (missing deps?)"
    exit 2
fi

# Parse results
has_fail=false
has_warn=false

while IFS= read -r line; do
    location=$(echo "$line" | jq -r '.location')
    ssim=$(echo "$line" | jq -r '.ssim // "N/A"')
    status=$(echo "$line" | jq -r '.status // "error"')
    error=$(echo "$line" | jq -r '.error // empty')

    if [[ -n "$error" ]]; then
        echo -e "\033[0;31mERROR:\033[0m $location: $error"
        has_fail=true
    elif [[ "$status" == "pass" ]]; then
        echo -e "\033[0;32mOK:\033[0m $location: SSIM=$ssim"
    elif [[ "$status" == "warn" ]]; then
        echo -e "\033[0;33mWARNING:\033[0m $location: SSIM=$ssim (below warning threshold)"
        has_warn=true
    else
        echo -e "\033[0;31mFAIL:\033[0m $location: SSIM=$ssim (below failure threshold)"
        has_fail=true
    fi
done <<< "$output"

if [[ "$has_fail" == "true" ]]; then
    if [[ "$VISUAL_REGRESSION_BLOCKING" == "true" ]]; then
        exit 1
    else
        exit 2
    fi
elif [[ "$has_warn" == "true" ]]; then
    exit 2
fi

exit 0
