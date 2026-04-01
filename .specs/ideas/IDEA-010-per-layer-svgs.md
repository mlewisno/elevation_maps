---
title: "Per-Layer SVG Output in Addition to Combined"
status: Declined
created: 2026-03-31
source: user
declined_reason: "Already implemented — write_per_layer_svgs() in svg/writer.py"
---

# IDEA-010: Per-Layer SVG Output

Output both a single combined multi-layer SVG AND individual SVG files
per layer in a subfolder.

```
output/kauai/
  topo_map.svg              # Combined (current behavior)
  layers/
    layer-00-water.svg      # Individual layers
    layer-01-water.svg
    ...
    layer-09-land.svg
    frame.svg
```

**Why**:
- Some laser workflows prefer loading one layer at a time
- Easier to cut layers from different materials (e.g., blue acrylic for
  water, plywood for land)
- Simpler to re-cut a single damaged layer without re-importing everything
- Some laser software may handle single-layer SVGs more reliably

**Implementation**: Straightforward — call write_svg once per layer with
a filtered GeoDataFrame. The combined SVG stays as-is.
