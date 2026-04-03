---
title: "2D Rendered Preview for AI Agent Validation"
status: In Progress
created: 2026-04-02
epic: enhancements
promoted_from: IDEA-011
depends_on: [FEAT-003, FEAT-004]
---

# FEAT-012: 2D Rendered Preview for AI Agent Validation

> Promoted from IDEA-011

## Summary

Generate a top-down 2D PNG showing all contour layers as filled, color-coded
polygons. Unlike the SVG (stroke-only) and 3D render (perspective), this
flat raster image is directly readable by multimodal AI models, enabling
automated visual validation of pipeline output.

## Requirements

### Functional

**2D Render Output**
- Accept `--render-2d` CLI flag
- Render each layer as filled polygons from a top-down view
- Use distinct color gradient: blues for water, greens/browns for land
- Layer boundaries visible through color stepping (not just outlines)
- Output as PNG alongside SVG (e.g., `output/render_2d.png`)

**Legend**
- Include a color legend showing layer numbers and elevation ranges
- Legend positioned outside the map area (right side or bottom)

**Resolution**
- Default ~1200px wide, aspect ratio matching the map
- Sufficient detail for AI model inspection of contour shapes

### Non-Functional
- Generation should complete in under 5 seconds
- No additional dependencies beyond matplotlib (already in core deps)
- Output must be a standard PNG readable by the Read tool

## Technical Approach

1. Reuse `_layer_color()` and `_collect_polygons()` from `render/renderer.py`
2. Use matplotlib 2D figure with `fill()` or `PatchCollection` for polygons
3. Render layers bottom-to-top so higher layers overlap lower ones
4. Add colorbar or discrete legend mapping colors to elevation ranges
5. Save with `savefig()` at specified DPI

## Files to Create/Modify

- `topo2laser/render/renderer.py` — Add `render_2d()` function
- `topo2laser/cli.py` — Add `--render-2d` flag
- `topo2laser/pipeline.py` — Wire 2D render stage
- `tests/test_render.py` — Add tests for 2D render

## Acceptance Criteria

- [ ] `--render-2d` generates a top-down PNG with filled color layers
- [ ] Water layers use blue gradient, land layers use green/brown gradient
- [ ] Layer boundaries are visually distinguishable
- [ ] Output resolution sufficient for AI inspection (~1200px wide)
- [ ] Legend shows layer elevation ranges
- [ ] Claude Code can read the PNG via Read tool and describe what it sees
