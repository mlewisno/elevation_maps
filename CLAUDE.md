# Project: Elevation Maps — Topo Relief Laser Cutter Pipeline

## Overview
Python CLI pipeline that converts geographic elevation data into layered SVG
files for laser cutting topographic relief maps. Each SVG layer represents a
contour band that, when cut from sheet material and stacked, produces a
physical 3D relief of the terrain.

## Import Core Guidance
@~/code/agent_guidance/CLAUDE.md

## Tech Stack
- Language: Python 3.12+
- CLI Framework: TBD (click or typer)
- Geo libraries: rasterio, shapely, GDAL
- SVG generation: svgwrite or svgpathtools
- Data sources: USGS 3DEP, OpenTopography, OSM Overpass
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
  landmarks/             # OSM landmark/label queries
  alignment/             # Registration marks, engraved guides
tests/                   # pytest test suite
.specs/                  # Feature specs, ADRs, ideas
scripts/hooks/           # Git hooks & validators
```

## Common Tasks

### Install Dependencies
```bash
pip install -e ".[dev]"
```

### Run Tests
```bash
pytest
```

### Run Pipeline (target CLI)
```bash
topo2laser --bbox "37.7,-119.8,37.9,-119.5" --layers 8 --output yosemite/
```

### Format Code
```bash
black topo2laser/ tests/ && ruff check --fix topo2laser/ tests/
```

## Project-Specific Rules
- All geo coordinates use (lat, lon) order in user-facing APIs, but internal
  processing may use (lon, lat) per geo library conventions. Document which
  convention each function uses.
- SVG output must be laser-cutter compatible: no fills, stroke-only paths,
  units in mm.
- Keep pipeline stages independent — each stage reads files/data and writes
  files/data. No hidden coupling between stages.
