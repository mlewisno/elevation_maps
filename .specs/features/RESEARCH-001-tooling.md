---
title: Tooling Research — Elevation Data, Contours, SVG, Landmarks
status: Complete
created: 2026-03-31
---

# RESEARCH-001: Tooling Research

## Elevation Data Sources

| Source | Resolution | Coverage | Python Access | Notes |
|--------|-----------|----------|---------------|-------|
| USGS 3DEP | 1m (lidar), 10m (nationwide) | US only | **py3dep** | Best for US. Lidar-derived 1m is exceptional for small areas |
| Copernicus GLO-30 | 30m | Global (inc. high latitudes) | OpenTopography API, **rasterio** | Best modern global DEM. Better than SRTM in vegetation/steep terrain |
| SRTM | 30m | 60N–56S | **elevation** package | Well-understood, easy to obtain. Good fallback |
| OpenTopography | Varies (hosts others) | Global | REST API (free key) | One-stop shop, also hosts lidar datasets |
| Mapzen Terrain Tiles | ~30m (tiled PNGs) | Global | HTTP tile URLs | Repackaged data, PNG quantization artifacts. Good for preview |
| ALOS AW3D30 | 30m | Global | JAXA registration | Alternative to SRTM/Copernicus |

**Recommendation**: py3dep for US, Copernicus GLO-30 via OpenTopography for global.
rasterio as the universal raster I/O layer.

## Contour Generation Approaches

### Option A: GDAL `gdal_contour -p` (polygon mode)
- Battle-tested, handles edge cases, fast on large rasters
- The `-p` flag produces filled contour polygons (bands between elevations)
- Output to GeoJSON/GeoPackage, load with geopandas/shapely
- Python: call via subprocess or `osgeo.gdal.ContourGenerateEx()`
- GDAL bindings are notoriously awkward in Python

### Option B: rasterio threshold + `rasterio.features.shapes()`
- For each layer height h: mask where elevation >= h, vectorize to polygon
- Produces exact closed polygons with holes
- **Downside**: pixelated/staircase edges (follows raster cells) — needs smoothing
- Cleanest pure-Python approach for per-layer polygons

### Option C: matplotlib `contourf` extraction
- Use `plt.contourf()` on the DEM array, extract paths as shapely polygons
- Fine control over smoothing and levels
- Paths are in pixel coordinates — need geo-transform back
- Careful handling of interior rings (holes) required

### Polygon Smoothing (needed for all approaches)
- **Douglas-Peucker**: `polygon.simplify(tolerance)` — reduces vertices, keeps angular look
- **Chaikin corner-cutting**: Iterative smoothing, ~15 lines of numpy. Best aesthetic result
- **Buffer trick**: `polygon.buffer(d).buffer(-d)` — rounds sharp corners
- **Bezier fitting**: scipy interpolation → svgpathtools curves

**Recommendation**: Start with GDAL `gdal_contour -p` for robustness. Fall back
to rasterio threshold+shapes if we want pure-Python. Add Chaikin smoothing.

## SVG Generation

### svgwrite (recommended)
- Pure Python, complete SVG spec, mature
- Full control over units, stroke properties, grouping
- Convert shapely polygons → SVG path d-strings
- No geometric operations (geometry handled upstream)

### svgpathtools
- Read/write/manipulate SVG paths, Bezier curves
- Good for smoothing polylines into cubic Bezier curves
- Complementary to svgwrite

### Laser Cutter SVG Requirements
- **Units**: Set `width="300mm" height="200mm"` — laser software interprets literally
- **Strokes**: Hairline (0.001mm or 0.01mm). Strokes = cut lines
- **Fills**: Filled areas = engrave
- **Color coding** (common convention):
  - Red (#FF0000) = cut through
  - Blue (#0000FF) = score/mark
  - Black (#000000) = raster engrave
- **Paths**: Must be closed (SVG `Z` command). No overlapping cut lines (double-cut)
- **DPI**: Explicit mm units avoid 96 DPI ambiguity

## Landmark Data

### osmnx (recommended)
- `osmnx.features_from_bbox(north, south, east, west, tags={"natural": "peak"})`
- Returns GeoDataFrame with names, elevations, geometries
- Also works for lakes, rivers, towns

### Overpass QL (direct)
- POST to `https://overpass-api.de/api/interpreter`
- More control, fewer dependencies
- Key tags: `natural=peak`, `natural=water`, `waterway=river`, `place=city|town|village`

## Prior Art (Existing Projects)

| Project | What It Does | Relevance |
|---------|-------------|-----------|
| TouchTerrain | DEM → 3D-printable STL | DEM acquisition logic reusable; outputs STL not SVG |
| 3D_Elevation_Map_Generator | Layered elevation maps (Python, SRTM) | Closest prior art |
| OpenSCAD approaches | DEM → heightfield → slice → DXF/SVG | Different toolchain but same concept |
| QGIS manual workflows | Contour generation + SVG/DXF export | Scriptable via PyQGIS but heavy dependency |

No single project does exactly what we want (DEM → laser-ready layered SVGs
with alignment features). The pipeline needs to be built, but each stage has
well-maintained libraries.

## Recommended Dependency Stack

```
rasterio          # Raster I/O (reads GeoTIFF, handles CRS)
py3dep            # USGS 3DEP elevation data fetching
shapely>=2.0      # Geometry operations (simplify, buffer, offset)
geopandas         # GeoDataFrame for polygon collections
svgwrite          # SVG file generation
click             # CLI framework
requests          # HTTP for OSM Overpass queries
pyproj            # Coordinate transforms (via rasterio/geopandas)
GDAL              # gdal_contour for contour polygon generation
```

Optional:
```
osmnx             # Convenient OSM queries (pulls in networkx)
svgpathtools      # Bezier curve smoothing for SVG paths
matplotlib        # Alternative contour generation, preview rendering
```
