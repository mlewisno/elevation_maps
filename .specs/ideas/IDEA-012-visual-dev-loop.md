---
title: "Visual Development Feedback Loop via 2D Previews"
status: Promoted
created: 2026-04-02
source: user
promoted_to: FEAT-013
ice_scores:
  impact: 10
  confidence: 7
  ease: 7
  total: 490
---

# IDEA-012: Visual Development Feedback Loop via 2D Previews

## Problem

When Claude Code makes changes to contour generation, SVG output, projection,
or rendering logic, the only validation available is unit tests and file
existence checks. There's no automated way to verify that the *visual output*
is correct — that coastlines look right, layers are properly stacked, polygons
aren't broken, etc.

This means every pipeline change requires the user to manually inspect the
output, creating a bottleneck in the development loop.

## Proposed Solution

Create a development workflow (and optionally a slash command or hook) that
uses FEAT-012's `--render-2d` output as a visual validation step during
feature development. After making changes, Claude Code would:

1. Run the pipeline on a reference bounding box (e.g., Kaua'i)
2. Generate the 2D preview PNG
3. Fetch a reference map image (satellite or topo map) for the same bbox
4. Read both PNGs with the multimodal Read tool
5. Compare: do coastlines align? Are islands present? Do elevation bands
   correlate with terrain features visible in the reference?
6. Analyze the contour image for common issues:
   - Missing or empty layers
   - Broken/invalid polygon shapes
   - Coastline artifacts from projection
   - Layer ordering issues (water above land)
   - Missing frame or alignment marks
7. Report findings or iterate on fixes

**Reference map sources:**
- OpenStreetMap static tiles via URL (free, no API key)
- USGS topo map tiles
- OpenTopoMap (topo contours overlaid on OSM)
- Cache reference images per bbox to avoid repeated fetches

**Potential implementations:**
- A `/validate-visual` slash command that runs the pipeline and inspects output
- A reference image fetcher that grabs a map tile for the same bbox
- A post-commit hook that generates a preview on pipeline code changes
- Integration into `/feature complete` to auto-validate before PR creation

## Value Signal

- Dramatically reduces human review burden for pipeline changes
- Catches visual regressions that unit tests miss
- Enables more autonomous feature development on the pipeline
- Reference image baselines could serve as visual regression tests

## Open Questions

- What reference locations should be used? (Kaua'i is good for coast/ocean,
  Duluth for lake/land, maybe a mountainous area for high layer counts)
- Should we store reference "known good" PNGs for comparison?
- How reliable is AI visual inspection for subtle issues like projection
  artifacts or slightly wrong coastlines?

## Dependencies

- Requires FEAT-012 (2D rendered preview) to be implemented first

## Prioritization Notes (2026-04-02)

ICE 490 (I:10 C:7 E:7). Promoted to FEAT-013. Impact is maximum because
this fundamentally changes how autonomously Claude Code can develop pipeline
features — from blind code changes to visually-validated iterations.
Confidence slightly lower because AI visual comparison reliability is
unproven. Ease moderate because it requires the reference map fetcher plus
workflow integration.
