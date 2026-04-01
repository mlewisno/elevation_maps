---
title: "High-Resolution Land Elevation via 3DEP"
status: Draft
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: [FEAT-002]
---

# FEAT-008: High-Resolution Land Elevation via 3DEP

## Summary

Merge USGS 3DEP high-resolution land elevation data (10m or 1m) on top of
the ETOPO base layer to dramatically improve contour smoothness and terrain
detail for US locations. ETOPO at 15 arc-second (~450m) is adequate for
ocean bathymetry but produces blocky land contours.

## Requirements

### Functional
- Fetch 3DEP data via `py3dep` for the land portion of the bounding box
- Resample to match ETOPO grid or use 3DEP's native resolution
- Merge: use 3DEP values where elevation > 0 (land), ETOPO where < 0 (ocean)
- Handle the coastline boundary seamlessly (no gaps or seams)
- Fall back to ETOPO-only for non-US locations

### Non-Functional
- 3DEP fetch should be cached like ETOPO
- Should not significantly increase pipeline runtime (< 30s additional)

## Technical Approach

1. Use `py3dep` to fetch 10m DEM for the bbox
2. Reproject ETOPO and 3DEP to the same CRS and resolution
3. Create a land mask from 3DEP (elevation > 0)
4. Composite: 3DEP where land, ETOPO where ocean
5. Write merged result as single GeoTIFF
6. Cache the merged result

## Files to Create/Modify

- `topo2laser/elevation/sources.py` — Add `fetch_3dep()` function
- `topo2laser/elevation/merge.py` — New: raster merging logic
- `topo2laser/elevation/fetcher.py` — Add merge step to fetch_elevation()
- `tests/test_elevation.py` — Add merge tests

## Open Questions

- What 3DEP resolution to use? 10m is 45x more detailed than ETOPO.
  For a 500mm map of Kaua'i, 10m → ~11,000 pixels across. That's plenty.
- How to handle the coastline seam? Buffer the land mask slightly to
  avoid gaps between data sources at the shoreline.

## Acceptance Criteria

- [ ] Kaua'i land contours are visibly smoother than ETOPO-only
- [ ] Ocean contours still use ETOPO (unchanged)
- [ ] No visible seam at the coastline
- [ ] Non-US locations fall back to ETOPO gracefully
- [ ] Cached after first fetch
