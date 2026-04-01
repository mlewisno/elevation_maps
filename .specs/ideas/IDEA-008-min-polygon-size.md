---
title: "Configurable Minimum Polygon Size Filter"
status: Captured
created: 2026-03-31
source: user
---

# IDEA-008: Configurable Minimum Polygon Size Filter

Some layers produce very small disconnected polygons (tiny islets, isolated
peaks, small seafloor features). These are impractical to laser cut — they
may be too small to handle, burn during cutting, or get lost during assembly.

**Current behavior**: There's a basic `MIN_AREA_FRACTION` filter in
`contours/generator.py` (0.05% of total raster area), but it's not
user-facing and may not be aggressive enough.

**Proposed**:
- Add `--min-polygon-mm` CLI option (minimum polygon dimension in mm after scaling)
- Filter out polygons whose bounding box is smaller than the threshold in both dimensions
- Default to something like 3-5mm (roughly the kerf width x10)
- Could also offer `--keep-small-polygons` to disable filtering entirely
- Log which polygons were dropped so the user can adjust

**Why not just merge small polygons into nearby larger ones?**
That's harder and may produce unnatural shapes. Dropping is simpler and
for laser cutting, a 2mm polygon is genuinely uncuttable anyway.
