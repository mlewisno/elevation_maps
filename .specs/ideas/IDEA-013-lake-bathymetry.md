---
title: "Great Lakes Bathymetry Data Source"
status: Promoted
created: 2026-04-03
source: user
promoted_to: FEAT-014
ice_scores:
  impact: 8
  confidence: 7
  ease: 5
  total: 280
---

# IDEA-013: Great Lakes Bathymetry Data Source

## Problem

ETOPO only covers ocean bathymetry. For freshwater lakes like Lake Superior,
ETOPO reports the land surface elevation (~183m) rather than lake depth.
3DEP also treats lake areas as land. This means the Duluth/Twin Ports area
renders as all-land with no water layers, missing the dramatic lake
bathymetry that would make it a compelling topo map.

## Proposed Solution

Integrate NOAA GLERL (Great Lakes Environmental Research Laboratory)
bathymetry data as an additional data source for the Great Lakes:

- **Data source**: NOAA GLERL bathymetry grids
  (https://www.ngdc.noaa.gov/mgg/greatlakes/)
- Detect when bbox overlaps a Great Lake
- Fetch lake bathymetry and merge with land elevation
- Lake surface becomes the water/land boundary (not sea level)

## Value Signal

- Enables compelling topo maps of Great Lakes coastal cities (Duluth,
  Marquette, Traverse City, etc.)
- Lake Superior has dramatic underwater features (deep trenches, ridges)
- Extends the tool beyond ocean-only bathymetry

## Prioritization Notes (2026-04-03)

Promoted to FEAT-014. One of the three core use cases for this tool
(ocean, lake, all-land). Duluth reference case is blocked on this.
