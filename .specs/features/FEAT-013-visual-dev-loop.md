---
title: "Visual Development Feedback Loop with Reference Map Comparison"
status: Draft
created: 2026-04-02
epic: developer-experience
promoted_from: IDEA-012
depends_on: [FEAT-012]
---

# FEAT-013: Visual Development Feedback Loop with Reference Map Comparison

> Promoted from IDEA-012

## Summary

Create a development workflow where Claude Code visually validates pipeline
output by generating a 2D contour preview (FEAT-012) and comparing it against
a reference map image (satellite or topographic) for the same bounding box.
This enables autonomous detect-and-fix cycles: the agent makes a change, runs
the pipeline, reads both images, checks that coastlines/terrain/layers
correlate with reality, and iterates if something looks wrong.

## Requirements

### Functional

**Reference Map Fetcher**
- Fetch a static map image for a given bounding box
- Support multiple sources: OSM tiles, OpenTopoMap, USGS topo
- Output as PNG at comparable resolution to the 2D contour preview
- Cache fetched images by bbox hash to avoid repeated network calls

**Visual Comparison Workflow**
- Generate contour 2D preview via `--render-2d` (FEAT-012)
- Fetch or load cached reference map for the same bbox
- Present both images for AI agent inspection (Read tool)
- Agent checks for:
  - Coastline alignment (do island shapes match?)
  - Terrain correlation (do elevation bands match visible features?)
  - Missing features (islands, peninsulas, lakes present in reference?)
  - Obvious artifacts (broken polygons, projection warping)

**Integration Points**
- `/validate-visual` slash command for on-demand validation
- Optional integration into `/feature complete` for pipeline features
- Reference test locations: Kaua'i (coast/islands), Duluth (lake/urban)

**Reference Image CLI**
- `--fetch-reference` flag to save a reference map image alongside output
- Stored as `output/reference_map.png`

### Non-Functional
- Reference fetch should complete in under 10 seconds
- Cached images stored in the same cache directory as elevation data
- No API keys required (use free tile sources)
- Respect tile server usage policies (user-agent, rate limiting)

## Technical Approach

1. Create `topo2laser/reference/fetcher.py` — fetch OSM/topo map tiles
   for a bbox, stitch into a single image at target resolution
2. Use `contextily` library (already used in geo Python workflows) or
   direct tile URL fetching with `requests` + `PIL`
3. Add `/validate-visual` skill that orchestrates: run pipeline →
   generate 2D preview → fetch reference → read both → report
4. Cache reference images keyed on bbox hash + source

## Files to Create/Modify

- `topo2laser/reference/__init__.py` — Module init
- `topo2laser/reference/fetcher.py` — Map tile fetching and stitching
- `topo2laser/cli.py` — Add `--fetch-reference` flag
- `topo2laser/pipeline.py` — Wire reference fetch stage
- `.claude/skills/validate-visual/SKILL.md` — Slash command for validation
- `tests/test_reference.py` — Unit tests

## Open Questions

- Best tile source for correlation? OpenTopoMap shows contours which could
  be confusing. Plain OSM or satellite may be better for coastline comparison.
- Should the agent compare images programmatically (pixel diff, SSIM) in
  addition to visual inspection, or is AI vision sufficient?
- How to handle bbox areas with no reference tiles (remote ocean areas)?

## Acceptance Criteria

- [ ] Reference map image fetched and cached for a given bbox
- [ ] `--fetch-reference` saves reference map alongside output
- [ ] `/validate-visual` runs pipeline, fetches reference, reads both images
- [ ] Claude Code can identify coastline mismatches between contour and reference
- [ ] Reference images cached — second fetch for same bbox uses cache
- [ ] Works for both Kaua'i (ocean/islands) and Duluth (lake/urban) test areas
