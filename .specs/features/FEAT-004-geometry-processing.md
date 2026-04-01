---
title: "Geometry Processing (Simplify, Scale, Align)"
status: Complete
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: [FEAT-003]
---

# FEAT-004: Geometry Processing

## Summary

Process raw contour polygons into laser-ready geometry: simplify for clean
cuts, project and scale to physical dimensions (mm), apply kerf compensation,
and generate alignment outlines.

## Requirements

### Functional

**Simplification**
- Smooth jagged contour edges for clean laser cuts
- Support Douglas-Peucker simplification with configurable tolerance
- Support Chaikin corner-cutting for smoother curves
- Default tolerance based on kerf width (~0.5x kerf)

**Projection and Scaling**
- Project from geographic coordinates (lat/lon) to metric (mm)
- Use Lambert Azimuthal Equal Area projection centered on the bbox
- Scale to fit within user-specified width (and optional height)
- Preserve aspect ratio
- Constrain output to xTool P2 working area (600mm x 305mm) with warning
  if the map exceeds it

**Kerf Compensation**
- Offset cut paths outward by half kerf width
- Alignment engrave outlines use true geometry (no offset)
- Kerf width is user-configurable (default 0.2mm)

**Alignment Outlines**
- For each layer N, generate the outline of layer N+1 as an engrave path
- This outline is engraved onto layer N's surface as a visual alignment guide
- No alignment outline on the topmost layer

**Frame Generation**
- Optional rectangular frame piece
- Frame inner cutout matches the outermost contour (or full bbox)
- Frame adds a configurable border width around the map

### Non-Functional
- Processing should complete in under 5s for typical polygon sets

## Technical Approach

1. Simplify polygons with `shapely.simplify()` or custom Chaikin smoothing
2. Reproject with `pyproj` / `geopandas.to_crs()` to LAEA
3. Scale coordinates: compute scale factor from geographic extent → target mm
4. Apply kerf offset with `shapely.buffer(kerf/2)` on cut paths
5. Generate alignment outlines: for each layer, extract boundary of next layer
6. Generate frame: create rectangle, subtract innermost contour for cutout

## Files to Create/Modify

- `topo2laser/contours/simplify.py` — Polygon smoothing/simplification
- `topo2laser/svg/projection.py` — CRS projection and mm scaling
- `topo2laser/alignment/kerf.py` — Kerf compensation
- `topo2laser/alignment/outlines.py` — Layer alignment outline generation
- `topo2laser/alignment/frame.py` — Frame piece generation
- `tests/test_geometry.py` — Unit tests

## Open Questions

- Q3 from vision: Exact simplification tolerance (needs physical testing)
- Q9 from vision: Frame clearance/tolerance dimensions

## Acceptance Criteria

- [ ] Polygons are simplified without losing terrain character
- [ ] Output coordinates are in mm, not degrees
- [ ] Aspect ratio is preserved
- [ ] Kerf-compensated paths are offset outward by half kerf
- [ ] Each layer has an alignment outline of the layer above
- [ ] Frame piece is generated with correct inner cutout
- [ ] Warning displayed if map exceeds 600mm x 305mm
