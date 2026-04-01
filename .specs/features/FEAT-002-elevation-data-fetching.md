---
title: "Elevation + Bathymetry Data Fetching"
status: Draft
created: 2026-03-31
epic: core-pipeline
vision: FEAT-001
depends_on: []
---

# FEAT-002: Elevation + Bathymetry Data Fetching

## Summary

Fetch and merge elevation (land) and bathymetric (ocean depth) raster data
for a given bounding box, producing a single GeoTIFF where positive values
represent land elevation and negative values represent ocean depth.

## Requirements

### Functional
- Accept a bounding box as (south, west, north, east) decimal degrees
- Fetch ETOPO Global Relief Model data as the base layer (combined land+ocean)
- Fetch USGS 3DEP data for higher-resolution land elevation (US locations)
- Merge high-res land data over ETOPO ocean data at the coastline boundary
- Output a single GeoTIFF raster with consistent CRS and resolution
- Cache downloaded raster data to avoid re-fetching

### Non-Functional
- Fetch should complete in under 30s for a typical island-sized bounding box
- Handle network errors gracefully with retry logic
- Support offline mode using cached data

## Technical Approach

1. Use `rasterio` for all raster I/O
2. Use `py3dep` to fetch USGS 3DEP data (US locations)
3. Fetch ETOPO data via NOAA NCEI grid extract or pre-downloaded tiles
4. Reproject both to a common CRS (UTM zone or LAEA centered on bbox)
5. Resample to matching resolution (use the higher-res grid)
6. Merge: use 3DEP for land pixels, ETOPO for ocean pixels
7. Write merged result as GeoTIFF

## Files to Create/Modify

- `topo2laser/elevation/fetcher.py` — Main fetch orchestration
- `topo2laser/elevation/sources.py` — Data source adapters (ETOPO, 3DEP)
- `topo2laser/elevation/merge.py` — Raster merging logic
- `tests/test_elevation.py` — Unit tests

## Open Questions

- Q1 from vision: What resolution actually matters given laser kerf?
- Q2 from vision: Best merge strategy at coastline boundary?
- ETOPO access method: direct download vs API vs pre-packaged tiles?

## Acceptance Criteria

- [ ] Given Kaua'i bounding box, fetches combined land+ocean raster
- [ ] Land areas have positive elevation values
- [ ] Ocean areas have negative depth values
- [ ] Output is a single GeoTIFF with valid CRS metadata
- [ ] Second run for same bbox uses cache (no re-download)
- [ ] Works for Duluth, MN bounding box (Lake Superior bathymetry)
