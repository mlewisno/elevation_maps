# Project: Elevation Maps — Topo Relief Laser Cutter Pipeline

## Overview
Python CLI pipeline that converts geographic elevation data into layered SVG
files for laser cutting topographic relief maps. Each SVG layer represents a
contour band that, when cut from sheet material and stacked, produces a
physical 3D relief of the terrain.

## Import Core Guidance
@~/code/agent_guidance/CLAUDE.md

## Tech Stack
- Language: Python 3.13
- Package manager: uv
- CLI Framework: click
- Geo libraries: rasterio, shapely, GDAL, geopandas, pyproj
- SVG generation: svgwrite, svgpathtools
- 3D rendering: matplotlib
- Data sources: USGS 3DEP (py3dep), ETOPO (OPeNDAP), OSM Overpass
- Testing: pytest
- Formatting: black, ruff

## Directory Structure
```
topo2laser/              # Main package
  cli.py                 # CLI entry point
  pipeline.py            # Orchestrates the full pipeline
  elevation/             # Fetch & process DEM data
  contours/              # DEM -> contour polygons
  svg/                   # Contour polygons -> laser-ready SVGs
  render/                # 3D preview rendering
  landmarks/             # OSM landmark/label queries
  alignment/             # Registration marks, engraved guides
tests/                   # pytest test suite
.specs/                  # Feature specs, ADRs, ideas
scripts/hooks/           # Git hooks & validators
```

## Common Tasks

### Install Dependencies
```bash
uv sync --extra dev
```

### Run Tests
```bash
uv run pytest
```

### Run Pipeline (target CLI)
```bash
uv run topo2laser --bbox "37.7,-119.8,37.9,-119.5" --layers 8 --output yosemite/
```

### Format Code
```bash
uv run black topo2laser/ tests/ && uv run ruff check --fix topo2laser/ tests/
```

## Project-Specific Rules
- **Physical stacking constraint**: This tool produces layers for a physical
  3D laser-cut map. Every lower layer MUST be strictly larger than (or equal
  to) the layer above it. Layer 0 is the full rectangle base. Each subsequent
  layer uses a cumulative mask (everything >= threshold), never a band/ring.
  When stacked, higher layers sit on top of lower ones — if a lower layer
  doesn't extend under the layer above it, the physical map has unsupported
  pieces. Always validate that layer N's area >= layer N+1's area.
- All geo coordinates use (lat, lon) order in user-facing APIs, but internal
  processing may use (lon, lat) per geo library conventions. Document which
  convention each function uses.
- SVG output must be laser-cutter compatible: no fills, stroke-only paths,
  units in mm.
- Keep pipeline stages independent — each stage reads files/data and writes
  files/data. No hidden coupling between stages.
