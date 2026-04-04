---
title: "Vision: Topographic Relief Map Laser Cutting Pipeline"
status: Draft
created: 2026-03-31
updated: 2026-03-31
---

# topo2laser — Vision Document

## What We're Building

A Python CLI pipeline that converts geographic coordinates into multi-layer
SVG files for laser cutting topographic and bathymetric relief maps. When
cut from sheet material and stacked, the layers produce a physical 3D
representation of terrain and ocean depth.

The tool supports both **mountain/terrain maps** (layers stack upward from a
base) and **coastal/bathymetric maps** (land sits at the top, water depth
layers descend below). Most real maps combine both — an island like Kaua'i
has land elevation rising above sea level AND ocean shelves descending below.

## Target Output Styles

### Style 1: Framed Coastal/Bathymetric Map (primary)
- Rectangular frame border piece
- Land as the topmost layer(s), natural wood
- Water depth layers descend below land surface
- Water layers can be painted/stained blue by the user
- Labels engraved on appropriate layer surfaces
- Optional logo/compass rose in a corner
- Reference images: Portland ME, Seattle, Norwalk CT, Outer Banks

### Style 2: Framed Terrain Map
- Same frame structure
- Layers stack upward showing elevation gain
- All natural wood, shadows create depth
- Elevation labels optionally engraved on layer faces
- Reference images: mountain terrain close-ups

### Style 3: Small Ornament (future)
- 4-6 thin layers, no frame
- Island/feature centered, compact size
- Could include a hanging hole
- Example: Kaua'i Christmas ornament

## Test Locations

1. **Kaua'i + Ni'ihau, Hawai'i** — Island with dramatic terrain (Waimea
   Canyon, Na Pali Coast) surrounded by ocean shelf. Combines land elevation
   and bathymetry. First prototype target.
2. **Duluth, Minnesota** — City on Lake Superior with bluffs rising from the
   lakefront. Combines lake bathymetry with terrain. Second prototype.

## Pipeline Architecture

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  1. Fetch    │───>│ 2. Generate  │───>│ 3. Process   │───>│ 4. Generate  │
│  Elevation   │    │   Contours   │    │   Geometry   │    │    SVG       │
│  + Bathymetry│    │              │    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                                              │
                                              v
                                       ┌──────────────┐
                                       │ 5. Labels &  │
                                       │  Decorative  │
                                       │  Elements    │
                                       └──────────────┘
```

### Stage 1: Fetch Elevation + Bathymetry Data
- **Input**: Bounding box (lat/lon)
- **Output**: Merged GeoTIFF with both land elevation (positive) and ocean
  depth (negative values)
- **Data sources**:
  - Land (US): USGS 3DEP via py3dep (10m or 1m resolution)
  - Land (global): Copernicus GLO-30 via OpenTopography
  - Combined land+ocean: ETOPO Global Relief Model (NOAA)
  - High-res bathymetry (US coastal): NOAA BlueTopo/NBS
- **Strategy**: Fetch ETOPO as the base layer (provides both land and ocean
  in one raster), then overlay higher-resolution land data (3DEP) where
  available. The merged raster has positive values for land, negative for
  water, zero at sea level.

### Stage 2: Generate Contours
- **Input**: Merged DEM raster, layer parameters
- **Output**: Set of closed contour polygons, one per physical layer
- **Tool**: `gdal_contour -p` (polygon mode) — confirmed by multiple
  reference projects as the right tool
- **Layer calculation**: User provides material thickness + total height OR
  layer count. Pipeline computes elevation interval per layer.
  - Example: Kaua'i, elevation range -1000m to +1598m (Kawaikini peak).
    With 3mm material and 12 layers = 36mm total. Each layer spans ~216m
    of elevation.
- **Land layers**: Contours at elevation >= 0, stacking upward
- **Water layers**: Contours at elevation < 0, conceptually descending below
  the land surface (physically: each water layer is cut with land area
  removed, revealing the layer below)
- **Short contour filtering**: Remove contour fragments shorter than a
  minimum length to eliminate noise (per shamblog reference)

### Stage 3: Process Geometry
- **Simplify polygons**: Douglas-Peucker or Chaikin smoothing to remove
  micro-features that would cause poor cuts. Tolerance ≈ 0.5-1x laser kerf.
- **Kerf compensation**: Offset cut paths outward by half kerf width so cut
  pieces are the correct size. Engraved alignment outlines use true geometry
  (no offset).
- **Alignment outlines**: Engrave the outline of the layer above onto each
  layer's surface. This is the confirmed best approach — visual alignment
  guide, no extra hardware needed.
- **Frame piece**: Optional rectangular border. Innermost cutout follows the
  outermost contour (or the full bounding box for terrain-only maps).
- **Scale to physical dimensions**: Project from geographic coordinates to
  mm, fitting within the target width/height while preserving aspect ratio.
  Use Lambert Azimuthal Equal Area projection (per jbeda/laser-topo).
- **Mark water vs. land layers**: Tag each layer with metadata so users
  know which layers to paint/stain if desired.

### Stage 4: Generate SVG
- **Output**: Single multi-layer SVG file
- **Layer organization within SVG**: Named SVG groups per physical layer,
  containing:
  - Cut paths (stroke color: configurable, default red #FF0000)
  - Engrave paths — alignment outline of next layer (default blue #0000FF)
  - Engrave paths — labels/decorative elements (default black #000000)
- **SVG requirements for laser cutters**:
  - Units in mm (`width="600mm" height="305mm"`)
  - Hairline strokes (0.01mm) for cut lines
  - All paths closed (SVG `Z` command)
  - No overlapping cut paths (prevents double-cuts)
  - No fills on cut paths, stroke only
  - Text converted to paths (laser cutters need geometry, not fonts)
- **Layer naming**: `layer-01-land-0m-to-216m`, `layer-05-water-neg432m-to-neg216m`, etc.
- **Target software**: LightBurn (primary, used with xTool P2), also
  compatible with Inkscape and xTool Creative Space

### Stage 5: Labels & Decorative Elements
- **Location labels**: User provides a list of place names to label. Pipeline
  queries OSM for their coordinates and engraves them on the appropriate
  layer. Alternatively, label towns above a configurable population threshold.
- **Elevation labels**: Optionally engrave elevation values on layer faces.
- **Logo/compass rose**: Optional user-provided SVG placed in a configurable
  corner position. Engraved on the top land layer or frame.
- **Text-to-path**: All text must be converted to SVG paths before output
  (laser cutters don't render fonts).

## CLI Interface

```bash
# Minimal — just location and output
topo2laser --bbox "21.71,-160.5,22.3,-159.2" --output kauai/

# Full options
topo2laser \
  --bbox "21.71,-160.5,22.3,-159.2" \
  --material-thickness 3mm \
  --total-height 36mm \
  --width 500mm \
  --kerf 0.2mm \
  --include-bathymetry \
  --labels "Līhu'e,Waimea,Hanalei,Kapa'a,Po'ipū" \
  --label-towns-above 5000 \
  --logo logo.svg \
  --frame \
  --output kauai/

# Or specify layer count instead of total height
topo2laser \
  --bbox "46.7,-92.2,46.85,-91.9" \
  --material-thickness 3mm \
  --layers 10 \
  --width 400mm \
  --include-bathymetry \
  --frame \
  --output duluth/
```

### Material Thickness Presets
The CLI accepts any value, but provides named presets:
- `cardstock` = 1.5mm
- `thin-ply` = 3mm (1/8")
- `thick-ply` = 6mm (1/4")
- `acrylic-thin` = 3mm
- `acrylic-thick` = 6mm

## Hardware Context

**Laser cutter**: xTool P2 (55W CO2)
- Working area: 600mm x 305mm (23.6" x 12")
- Passthrough for longer pieces available
- Software: LightBurn for editing, xTool Creative Space for cutting
- SVGs are the primary import format

## Resolved Design Decisions

These questions from the original research have been answered through
reference analysis and user input.

| Decision | Resolution | Source |
|---|---|---|
| Contour algorithm | `gdal_contour -p` (polygon mode) | shamblog, jbeda/laser-topo |
| Cut vs engrave SVG convention | Red (#FF0000) = cut, Blue (#0000FF) = engrave outlines, Black (#000000) = engrave labels | shamblog, laser cutter convention |
| Alignment strategy | Engrave outline of next layer onto current layer surface | shamblog reference, user confirmation |
| Base/frame layer | Optional rectangular frame piece | User preference |
| Layer count | Calculated from material thickness + total height, OR user-specified | User preference |
| Output format | Single multi-layer SVG (named groups per layer) | User preference |
| Projection | Lambert Azimuthal Equal Area | jbeda/laser-topo |
| Road/street grid | Not included in initial version | User preference |
| Color guides | Out of scope; layers tagged as water/land for user painting | User preference |
| CLI framework | Click | Already stubbed |

## Open Research Questions (remaining)

### Data
- **Q1: Resolution vs. output size.** For a 500mm wide map of Kaua'i, what
  DEM resolution actually matters given ~0.2mm laser kerf? ETOPO at 15
  arc-second may be too coarse for land detail but fine for ocean. Need to
  test merging ETOPO (ocean) + 3DEP (land).
- **Q2: ETOPO + 3DEP merge strategy.** How to seamlessly blend the high-res
  land data with the lower-res ocean data at the coastline boundary?

### Contour Processing
- **Q3: Polygon simplification tolerance.** Need to test on xTool P2 with
  real plywood. Tolerance too low = slow cutting and burn marks. Too high =
  loss of terrain character.
- **Q4: Isolated small features.** Upper elevation layers may produce tiny
  disconnected polygons. Minimum area threshold? Keep, merge, or discard?
- **Q5: Short contour filtering threshold.** Shamblog filters by length,
  but what's the right minimum for our output scale?

### SVG & Cutting
- **Q6: Multi-layer SVG compatibility.** Verify that LightBurn and xTool
  Creative Space correctly import a single SVG with multiple named groups
  and interpret colors as separate operations.
- **Q7: Text-to-path font choice.** Need a clean, engraving-friendly font
  for labels. Candidates: a simple sans-serif or a cartographic style.

### Physical
- **Q8: Optimal layer count for Kaua'i.** Elevation range is ~2600m
  (from -1000m ocean to +1598m). With 3mm material, 12 layers = 36mm.
  Is that enough vertical resolution to capture the terrain character?
- **Q9: Frame dimensions and tolerances.** How much clearance between
  frame inner edge and outermost contour layer?

## Future Ideas (not in initial scope)

- Road/street grid engraving (OSM road network clipped per layer)
- Christmas ornament output mode (4-6 thin layers, small format)
- Towns above population threshold auto-labeled
- 3D preview rendering (stacked SVG with opacity, or WebGL)
- DXF output format for CNC routers
- Configurable color schemes for SVG layers
- Multiple data source auto-detection by region
- Batch processing (multiple locations from a config file)

## Acceptance Criteria

- [ ] Given Kaua'i bounding box, produces a multi-layer SVG
- [ ] SVG loads correctly in LightBurn with layers separated by color
- [ ] Both land and water contour layers are generated
- [ ] Layers are tagged as water or land in SVG metadata/naming
- [ ] Alignment outlines of the layer above are engraved on each layer
- [ ] Frame piece is generated when requested
- [ ] Pipeline calculates layer count from material thickness + total height
- [ ] Labels from user-provided list are placed on correct layers
- [ ] All text is converted to paths (no font dependencies in SVG)
- [ ] Output fits within xTool P2 working area (600mm x 305mm)
- [ ] Pipeline runs in under 60s for Kaua'i

## References

- [theshamblog: Making a Laser Cut Topo Map](https://theshamblog.com/making-a-laser-cut-topo-map-the-design-phase/) — QGIS-based workflow, 7-8 layers, alignment via engraved outlines
- [jbeda/laser-topo](https://github.com/jbeda/laser-topo) — Node.js tool using gdal_contour, LAEA projection, Mt. Rainier
- [NOAA ETOPO Global Relief Model](https://www.ncei.noaa.gov/products/etopo-global-relief-model) — Combined land+ocean elevation
- [NOAA Bathymetric Data](https://www.ncei.noaa.gov/products/bathymetry) — High-res coastal bathymetry
- Reference images: Portland ME, Seattle/Puget Sound, Norwalk CT, Kaua'i, Outer Banks NC, Duluth-style mountain terrain
