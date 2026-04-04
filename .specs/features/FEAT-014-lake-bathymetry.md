---
title: "Great Lakes Bathymetry Data Source"
status: Draft
created: 2026-04-03
epic: data-sources
promoted_from: IDEA-013
---

# FEAT-014: Great Lakes Bathymetry Data Source

> Promoted from IDEA-013

## Summary

Integrate NOAA GLERL bathymetry grids as a data source for freshwater
Great Lakes, enabling proper water depth layers for coastal cities like
Duluth. This is one of three core use cases: ocean (Kaua'i), lake
(Duluth), and all-land (Grand Canyon).

## Requirements

### Functional

- Detect when bbox overlaps a Great Lake boundary
- Fetch GLERL bathymetry grid for the relevant lake
- Merge lake bathymetry with land elevation (3DEP/ETOPO)
- Use lake surface elevation as the water/land boundary
- Cache downloaded GLERL data

### Non-Functional

- No API key required (NOAA public data)
- Graceful fallback if GLERL data unavailable
- Support all 5 Great Lakes

## Technical Approach

1. Download GLERL bathymetry grids from NOAA
2. Detect lake overlap by checking if bbox intersects known lake boundaries
3. Merge: use GLERL data where lake exists, 3DEP/ETOPO elsewhere
4. Adjust water/land boundary from sea level (0m) to lake surface elevation

## Open Questions

- GLERL data format and resolution?
- How to handle the water/land boundary at lake surface vs sea level?
- Should this extend to other large lakes (Tahoe, etc.)?

## Acceptance Criteria

- [ ] Duluth reference shows Lake Superior depth contours
- [ ] Water layers show actual lake floor bathymetry
- [ ] Land/water boundary at lake surface elevation (~183m for Superior)
- [ ] Other Great Lakes work with same approach
