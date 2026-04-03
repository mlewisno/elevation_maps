---
title: "Visual Development Feedback Loop via 2D Previews"
status: Captured
created: 2026-04-02
source: user
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
3. Read the PNG with the multimodal Read tool
4. Analyze the image for common issues:
   - Missing or empty layers
   - Broken/invalid polygon shapes
   - Coastline artifacts from projection
   - Layer ordering issues (water above land)
   - Missing frame or alignment marks
5. Report findings or iterate on fixes

**Potential implementations:**
- A `/validate-visual` slash command that runs the pipeline and inspects output
- A post-commit hook that generates a preview on pipeline code changes
- A reference image comparison (generate → diff against known-good baseline)
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
