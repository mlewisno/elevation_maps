---
title: "Multi-Layer SVG Generation"
status: Draft
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: [FEAT-004]
---

# FEAT-005: Multi-Layer SVG Generation

## Summary

Generate a single multi-layer SVG file from processed geometry. Each physical
layer is an SVG group containing cut paths, alignment engrave paths, and
label/decorative engrave paths, color-coded for laser cutter operation mapping.

## Requirements

### Functional

**SVG Structure**
- Single SVG file with dimensions in mm
- One named `<g>` group per physical layer
- Layer naming convention: `layer-NN-{water|land}-{min}m-to-{max}m`
- Layers ordered bottom-to-top in the SVG

**Color Coding**
- Cut paths: red (#FF0000) stroke, configurable
- Alignment engrave paths: blue (#0000FF) stroke, configurable
- Label/decorative engrave paths: black (#000000) stroke, configurable
- No fills on any paths

**Path Requirements**
- Hairline strokes (0.01mm width)
- All paths closed (end with SVG `Z` command)
- No overlapping cut paths between layers
- Shapely polygon exteriors → SVG path `d` attribute with `M`, `L`, `Z`

**Metadata**
- SVG title element with location name
- Comment or metadata per layer group: elevation range, water/land tag
- Layer number embedded in group `id` attribute

### Non-Functional
- SVG must load correctly in LightBurn, Inkscape, and xTool Creative Space
- File size should be reasonable (< 10MB for typical maps)

## Technical Approach

1. Use `svgwrite` to create the SVG document with mm units
2. For each layer (bottom to top):
   a. Create a named `<g>` group
   b. Convert cut polygon exterior/interior rings to SVG path `d` strings
   c. Add cut paths with red stroke
   d. Add alignment outline paths with blue stroke
   e. Add any label/decorative paths with black stroke
3. Write single SVG file

## Files to Create/Modify

- `topo2laser/svg/writer.py` — SVG document creation and writing
- `topo2laser/svg/paths.py` — Shapely geometry → SVG path conversion
- `topo2laser/svg/colors.py` — Color scheme configuration
- `tests/test_svg.py` — Unit tests (validate SVG structure, path closure)

## Open Questions

- Q6 from vision: Verify multi-layer SVG compatibility with LightBurn
  (need to test with a real file)

## Acceptance Criteria

- [ ] Single SVG output with one `<g>` group per layer
- [ ] Groups are named with layer number and elevation range
- [ ] Cut paths are red, engrave paths are blue/black
- [ ] All paths are closed and use hairline strokes
- [ ] SVG dimensions are in mm
- [ ] File opens correctly in Inkscape (manual verification)
- [ ] Water and land layers are distinguishable by group name
