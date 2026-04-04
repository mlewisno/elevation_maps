#!/usr/bin/env bash
#
# generate-reference.sh — Regenerate reference images for visual regression.
#
# Usage: ./scripts/generate-reference.sh [location]
#   No args: regenerate all locations
#   With arg: regenerate specific location (kauai, duluth)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REF_DIR="$PROJECT_ROOT/tests/reference"

generate_location() {
    local location="$1"
    local config="$REF_DIR/$location/config.json"

    if [[ ! -f "$config" ]]; then
        echo "ERROR: Config not found: $config"
        return 1
    fi

    echo "Generating reference for: $location"

    # Parse config.json
    local bbox material layers water_layers width high_res frame
    bbox=$(jq -r '.bbox' "$config")
    material=$(jq -r '.material_thickness' "$config")
    layers=$(jq -r '.layers' "$config")
    water_layers=$(jq -r '.water_layers' "$config")
    width=$(jq -r '.width' "$config")
    high_res=$(jq -r '.high_res' "$config")
    frame=$(jq -r '.frame' "$config")

    # Build CLI args
    local args=(
        --bbox "$bbox"
        --output "$REF_DIR/$location/output"
        --material-thickness "$material"
        --layers "$layers"
        --width "$width"
        --render-2d
        --render
    )

    if [[ "$water_layers" != "null" ]]; then
        args+=(--water-layers "$water_layers")
    fi
    if [[ "$high_res" == "true" ]]; then
        args+=(--high-res)
    fi
    if [[ "$frame" == "false" ]]; then
        args+=(--no-frame)
    fi

    # Run pipeline
    uv run topo2laser "${args[@]}"

    # Copy renders to reference directory
    cp "$REF_DIR/$location/output/render_2d.png" "$REF_DIR/$location/render_2d.png"
    cp "$REF_DIR/$location/output/render.png" "$REF_DIR/$location/render_3d.png" 2>/dev/null || true

    # Clean up output dir (keep only the reference PNGs)
    rm -rf "$REF_DIR/$location/output"

    echo "Reference images saved for: $location"
}

# Main
if [[ $# -gt 0 ]]; then
    generate_location "$1"
else
    for dir in "$REF_DIR"/*/; do
        location=$(basename "$dir")
        generate_location "$location"
    done
fi

echo "Done."
