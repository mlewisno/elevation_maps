---
title: "CLI Interface and Pipeline Orchestration"
status: Draft
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: [FEAT-002, FEAT-003, FEAT-004, FEAT-005]
---

# FEAT-007: CLI Interface and Pipeline Orchestration

## Summary

Wire all pipeline stages together into a Click CLI that accepts user
parameters and orchestrates the full flow from bounding box to SVG output.

## Requirements

### Functional

**CLI Options**
- `--bbox` (required): Bounding box as "south,west,north,east"
- `--output` / `-o` (required): Output directory
- `--material-thickness`: Thickness per layer (accepts mm value or preset name)
- `--total-height`: Desired total map height (alternative to --layers)
- `--layers`: Number of layers (alternative to --total-height)
- `--width`: Target physical width in mm (default: fit to laser bed)
- `--height`: Target physical height in mm (auto from aspect ratio if omitted)
- `--kerf`: Laser kerf width in mm (default: 0.2)
- `--include-bathymetry / --no-bathymetry`: Include ocean depth (default: yes)
- `--frame / --no-frame`: Generate frame piece (default: yes)
- `--labels`: Comma-separated list of place names to engrave
- `--label-towns-above`: Population threshold for auto-labeling
- `--logo`: Path to logo SVG file
- `--output` / `-o`: Output directory for SVG file

**Material Presets**
- `cardstock` = 1.5mm
- `thin-ply` = 3mm
- `thick-ply` = 6mm
- `acrylic-thin` = 3mm
- `acrylic-thick` = 6mm

**Pipeline Flow**
1. Parse and validate CLI arguments
2. Fetch elevation + bathymetry data (FEAT-002)
3. Generate contour polygons (FEAT-003)
4. Process geometry: simplify, project, scale, kerf, alignment (FEAT-004)
5. Generate SVG (FEAT-005)
6. Optionally add labels and decorative elements (FEAT-006)
7. Write output file and print summary

**Output Summary**
- Print layer count, elevation range per layer, water/land classification
- Print output file path and dimensions
- Warn if output exceeds laser bed size

### Non-Functional
- Full pipeline should complete in under 60s for Kaua'i
- Meaningful error messages for invalid inputs
- Progress output during long-running stages

## Files to Create/Modify

- `topo2laser/cli.py` — Rewrite existing stub with full options
- `topo2laser/pipeline.py` — Orchestration connecting all stages
- `tests/test_cli.py` — CLI argument parsing tests
- `tests/test_pipeline.py` — Integration tests

## Acceptance Criteria

- [ ] CLI parses all documented options
- [ ] Material presets resolve to correct mm values
- [ ] Pipeline runs end-to-end for Kaua'i bounding box
- [ ] Output summary shows layer breakdown
- [ ] Warnings displayed for oversized output
- [ ] `--help` documents all options clearly
