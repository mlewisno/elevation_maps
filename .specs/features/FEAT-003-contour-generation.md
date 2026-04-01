---
title: "Contour Polygon Generation"
status: Complete
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: [FEAT-002]
---

# FEAT-003: Contour Polygon Generation

## Summary

Convert a merged elevation/bathymetry raster into a set of closed contour
polygons — one per physical layer — suitable for laser cutting. Each polygon
represents the outline of a layer that will be cut from sheet material.

## Requirements

### Functional
- Accept a GeoTIFF raster (output of FEAT-002)
- Accept layer parameters: material thickness + total height, OR layer count
- Calculate elevation interval per layer from the raster's min/max values
- Generate filled contour polygons using `gdal_contour -p`
- Filter out short/tiny contour fragments (noise removal)
- Tag each polygon as water (elevation < 0) or land (elevation >= 0)
- Output polygons as a GeoDataFrame with layer number, elevation range,
  and water/land classification

### Layer Calculation
- User provides `material_thickness_mm` + `total_height_mm` → compute layer count
- OR user provides `material_thickness_mm` + `layer_count` → compute total height
- Elevation interval = (max_elevation - min_elevation) / layer_count
- Layers numbered from bottom (deepest water) to top (highest peak)

### Non-Functional
- Contour generation should complete in under 10s for typical rasters
- Polygons must be valid (no self-intersections, proper ring orientation)

## Technical Approach

1. Calculate elevation breakpoints from layer parameters
2. Run `gdal_contour -p` via subprocess or GDAL Python bindings
3. Load resulting polygons with `geopandas`
4. Validate and fix polygon geometry (`shapely.validation.make_valid`)
5. Filter out polygons below minimum area threshold
6. Filter out contour fragments below minimum length
7. Tag each polygon with layer number, elevation range, water/land flag
8. Return as GeoDataFrame

## Files to Create/Modify

- `topo2laser/contours/generator.py` — Contour generation orchestration
- `topo2laser/contours/layer_calculator.py` — Layer count/interval math
- `topo2laser/contours/filters.py` — Noise removal and polygon validation
- `tests/test_contours.py` — Unit tests

## Open Questions

- Q3 from vision: Polygon simplification tolerance (may belong in FEAT-004)
- Q4 from vision: How to handle isolated small features in upper layers
- Q5 from vision: Short contour filtering threshold
- Q8 from vision: Optimal layer count for Kaua'i's 2600m elevation range

## Acceptance Criteria

- [ ] Given Kaua'i raster + 12 layers, produces 12 polygon sets
- [ ] Each polygon is a valid closed geometry
- [ ] Polygons are tagged as water or land
- [ ] Tiny noise fragments are filtered out
- [ ] Layer count calculation works from thickness + height
- [ ] Layer count calculation works from thickness + count
