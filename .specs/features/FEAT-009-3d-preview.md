---
title: "3D Preview Rendering"
status: In Progress
created: 2026-04-01
epic: enhancements
promoted_from: IDEA-003
depends_on: [FEAT-003, FEAT-004]
---

# FEAT-009: 3D Preview Rendering

## Summary

Generate a visual 3D preview of the stacked contour layers so the user can
verify the map looks right before committing material to the laser cutter.
Renders the layer polygons as a stepped 3D surface, showing how the physical
relief will appear when assembled.

## Requirements

### Functional

**Render Output**
- Accept `--render` CLI flag to generate a 3D render after processing
- Render contour polygons as stacked layers at their physical heights
- Show the stepped/terraced appearance that matches the real laser-cut result
- Output as a static image (PNG) saved alongside the SVG output

**Rendering Approach**
- Use matplotlib's 3D plotting (`mpl_toolkits.mplot3d`) for initial implementation
- Render each layer polygon as a filled surface at its elevation
- Color layers by elevation (land/water distinction visible)
- Camera angle should show depth — isometric or slight perspective

**Interactivity (stretch)**
- Optionally open an interactive matplotlib window (`--render-interactive`)
- Allow rotation/zoom to inspect the result from different angles

### Non-Functional
- Preview generation should complete in under 10 seconds for typical maps
- Output image resolution sufficient for visual inspection (~1200px wide)
- Should not require any additional system dependencies beyond matplotlib

## Technical Approach

1. After contour generation and projection, collect layer polygons with their
   physical heights (layer index × material thickness)
2. For each layer, create a 3D polygon patch at the layer's Z height
3. Use `Poly3DCollection` to render filled polygons with elevation-based colors
4. Set camera angle, lighting, and aspect ratio for a natural topo appearance
5. Save to PNG with `savefig()`, optionally show with `plt.show()`

## Files to Create/Modify

- `topo2laser/preview/render.py` — 3D rendering logic
- `topo2laser/preview/__init__.py` — Module init
- `topo2laser/cli.py` — Add `--render` and `--render-interactive` flags
- `topo2laser/pipeline.py` — Wire render stage after SVG generation
- `tests/test_preview.py` — Unit tests

## Open Questions

- Should the preview show the frame piece if `--frame` is enabled?
- Color scheme: match SVG layer colors, or use a terrain colormap?
- Is matplotlib sufficient, or would pyvista/trimesh give better results
  for the stepped solid appearance?

## Acceptance Criteria

- [ ] `--render` flag generates a PNG showing the 3D stacked layers
- [ ] Layers are visually distinguishable by elevation
- [ ] Water and land layers have distinct coloring
- [ ] Render file saved alongside SVG output (e.g., `output/render.png`)
- [ ] `--render-interactive` opens a rotatable 3D view
- [ ] Render accurately represents the physical layer stacking
