---
title: "Road/Street Grid Engraving"
status: Considering
created: 2026-03-31
source: reference-analysis
ice_scores:
  impact: 6
  confidence: 5
  ease: 3
  total: 90
---

# IDEA-002: Road/Street Grid Engraving

Engrave road and street networks onto each layer's surface, clipped to that
layer's elevation band. This is a defining feature of commercial laser-cut
topo maps (visible in every reference image).

**What it would need**:
- Fetch OSM road network data for the bounding box
- Classify roads by type (highway, major road, local street)
- Clip road geometries to each layer's contour polygon
- Add clipped roads as engrave paths on each layer
- Filter by road importance based on map scale

**Complexity**: High — road network data is dense, clipping per layer is
geometrically expensive, and visual density needs careful tuning.
