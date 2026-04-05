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

    local water_level land_layers_cfg
    water_level=$(jq -r '.water_level' "$config")
    land_layers_cfg=$(jq -r '.land_layers' "$config")

    if [[ "$water_layers" != "null" ]]; then
        args+=(--water-layers "$water_layers")
    fi
    if [[ "$land_layers_cfg" != "null" ]]; then
        args+=(--land-layers "$land_layers_cfg")
    fi
    if [[ "$water_level" != "null" && "$water_level" != "0" ]]; then
        args+=(--water-level "$water_level")
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

    # Copy per-layer SVGs
    mkdir -p "$REF_DIR/$location/layers"
    cp "$REF_DIR/$location/output/layers/"*.svg "$REF_DIR/$location/layers/" 2>/dev/null || true
    cp "$REF_DIR/$location/output/topo_map.svg" "$REF_DIR/$location/topo_map.svg" 2>/dev/null || true

    # Generate per-layer 2D renders
    uv run python3 -c "
from pathlib import Path
from topo2laser.render import render_per_layer
from topo2laser.contours import calculate_layers, generate_contours
from topo2laser.svg.projection import project_and_scale
from topo2laser.elevation import BoundingBox
from topo2laser.contours.layer_calculator import resolve_thickness
import json, rasterio, numpy as np

config = json.load(open('$config'))
bbox = BoundingBox.from_string(config['bbox'])
cache_slug = f'{bbox.south:.2f}_m{abs(bbox.west):.2f}_{bbox.north:.2f}_m{abs(bbox.east):.2f}'
cache_dir = Path(f'.cache/elevation/{cache_slug}')
merged = cache_dir / 'merged.tif'
raster = merged if merged.exists() else cache_dir / 'etopo_merged.tif'

with rasterio.open(raster) as src:
    data = src.read(1)
    valid = data[~np.isnan(data)]

lc = calculate_layers(
    float(valid.min()), float(valid.max()),
    resolve_thickness(config['material_thickness']),
    layer_count=config.get('layers'),
    water_layers=config.get('water_layers'),
    water_level=config.get('water_level', 0),
)

land_mask = None
if config.get('high_res') and merged.exists():
    dep3 = list(cache_dir.glob('3dep_*.tif'))
    land_mask = dep3[0] if dep3 else None

from topo2laser.alignment import generate_alignment_outlines

gdf = generate_contours(raster, lc, land_mask_path=land_mask)
gdf, dims = project_and_scale(
    gdf, bbox.center_lat, bbox.center_lon,
    target_width_mm=float(config['width'].rstrip('mm')),
    bbox_south=bbox.south, bbox_west=bbox.west,
    bbox_north=bbox.north, bbox_east=bbox.east,
)
outlines = generate_alignment_outlines(gdf)
render_per_layer(gdf, dims.width_mm, dims.height_mm, Path('$REF_DIR/$location/layers'), alignment_outlines=outlines)
"

    # Clean up pipeline output dir
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
