---
title: Topographic Relief Map Laser Cutting Pipeline
status: Draft
created: 2026-03-31
---

# FEAT-001: Topographic Relief Map Laser Cutting Pipeline

## Summary

A Python CLI that takes a geographic bounding box and produces a set of SVG
files — one per layer — ready for laser cutting. When cut from sheet material
and stacked, the layers form a physical 3D relief map of the terrain.

## Pipeline Stages

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│  1. Fetch   │───>│ 2. Generate  │───>│ 3. Process  │───>│ 4. Generate  │
│  Elevation  │    │   Contours   │    │   Geometry   │    │    SVGs      │
│    Data     │    │              │    │              │    │              │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
      │                                      │                    │
      v                                      v                    v
  DEM raster              Landmark query          Alignment marks
  (GeoTIFF)               (OSM Overpass)          Registration holes
                                                  Engraved outlines
```

### Stage 1: Fetch Elevation Data
- Input: bounding box (lat/lon), desired resolution
- Output: GeoTIFF DEM raster
- Source: USGS 3DEP (US), SRTM (global), or OpenTopography

### Stage 2: Generate Contours
- Input: DEM raster, number of layers (or elevation interval)
- Output: Set of closed contour polygons, one per layer
- Each polygon represents everything at-or-above that elevation
- Bottom layer = full bounding box, top layer = just the peaks

### Stage 3: Process Geometry
- Simplify polygons for clean cuts (remove micro-features)
- Apply kerf compensation (offset paths by half material kerf)
- Add alignment features (registration holes, engraved outlines)
- Optionally add landmark labels
- Scale to target physical dimensions

### Stage 4: Generate SVGs
- One SVG per layer
- Cut lines (through-cut) on one layer/color
- Engrave lines (outline of layer above) on another layer/color
- Registration marks on a third layer/color
- Metadata: layer number, elevation range, scale

## CLI Interface (target)

```bash
# Basic usage
topo2laser --bbox "37.7,-119.8,37.9,-119.5" --layers 8 --output yosemite/

# With options
topo2laser \
  --bbox "37.7,-119.8,37.9,-119.5" \
  --layers 12 \
  --width 300mm \
  --height 400mm \
  --material-thickness 3mm \
  --kerf 0.2mm \
  --landmarks \
  --alignment dowel-holes \
  --exaggeration 2.5 \
  --output yosemite/
```

## Open Research Questions

### Data & Geography

- **Q1: Which elevation data source gives best results for laser cutting?**
  USGS 3DEP has ~1m resolution for the US but is large. SRTM is 30m global.
  For a 300mm wide map of a mountain, what resolution actually matters given
  that the laser kerf is ~0.2mm? We may be able to use coarser data and save
  download time. **Need to test with real data.**

- **Q2: How to handle areas partially covered by high-res data?**
  The bounding box might span multiple DEM tiles or cross a resolution
  boundary. Need a strategy for mosaicking and resampling.

- **Q3: Coordinate projection matters.**
  DEMs come in geographic (lat/lon) but physical output needs metric (mm).
  Which projection preserves area best for the target region? UTM is standard
  but zone-specific. Need to pick a sensible default and allow override.

### Contour Generation

- **Q4: Filled contours vs. contour lines?**
  `gdal_contour` produces isolines. We need filled regions (everything above
  elevation X). Options: `matplotlib.contourf`, `shapely` operations on
  isolines, or rasterize-then-vectorize. Which produces the cleanest polygons
  for laser cutting? **This is the critical algorithmic question.**

- **Q5: How to handle "islands" — isolated peaks that appear only in upper layers?**
  If a contour band has disconnected components, each becomes a separate
  physical piece. Options: keep them separate (need alignment strategy),
  add thin bridges (ugly but practical), or merge into the nearest component.

- **Q6: Polygon simplification threshold.**
  Too little simplification = noisy cuts, burned material, slow cutting.
  Too much = loss of terrain character. What's the right Douglas-Peucker
  tolerance relative to the laser kerf? Probably ~0.5-1x kerf width, but
  **need to test on a real cutter.**

- **Q7: How many layers is practical?**
  Depends on material thickness and desired vertical exaggeration. Need a
  calculator: given material thickness (e.g., 3mm plywood), desired height
  (e.g., 40mm), and elevation range (e.g., 1000m), compute layer count and
  elevation interval. User might specify either layer count OR interval.

### SVG & Laser Cutting

- **Q8: SVG format requirements for laser cutters.**
  Different laser software (LightBurn, Glowforge, LaserGRBL) may have
  preferences about SVG structure. Are there gotchas with nested groups,
  transforms, or path formats? Need to document compatibility.

- **Q9: Kerf compensation direction.**
  For the outline of each layer (which IS the piece), should we offset
  inward or outward? Outward means the cut piece is the right size.
  But for the engraved alignment outline (showing where the next layer
  sits), we'd want the actual outline without offset. Need to be precise
  about which paths get which treatment.

- **Q10: How to represent cut vs. engrave vs. score in SVG?**
  Common conventions: different colors (red=cut, blue=engrave, green=score)
  or different layers. Some cutters use stroke width. Need to pick a default
  and make it configurable.

### Alignment & Assembly

- **Q11: Dowel holes vs. engraved outlines vs. interlocking tabs?**
  - **Dowel holes**: Precise, requires drilling. 2-3 holes per layer.
  - **Engraved outlines**: Visual guide, less precise, no extra hardware.
  - **Tabs/slots**: Self-aligning but add visible features to edges.
  - Could support multiple strategies. Which to implement first?

- **Q12: How to handle the base layer?**
  Should the base (bottom) layer be a full rectangle that acts as a
  frame/backing? Or should it follow the lowest contour? A full rectangle
  provides a clean edge and mounting surface.

- **Q13: Glue-up strategy affects alignment features.**
  If using wood glue, the pieces need clamping pressure. Dowel holes help
  here. If using adhesive sheets or spray adhesive, engraved outlines
  might be sufficient. This is a physical fabrication question.

### Landmarks & Labels

- **Q14: How to place text labels on contour layers?**
  Labels need to sit on a flat area within a specific layer. Options:
  engrave on the layer surface, or engrave on the layer below where the
  labeled feature will sit. Need to figure out text-to-path conversion
  for SVG (laser cutters need paths, not text elements).

- **Q15: Which landmark types are useful?**
  Peaks, lakes, rivers, towns, trails? OSM has all of these but cluttering
  the map defeats the purpose. Need sensible defaults and filtering.

- **Q16: River/water features as special layers?**
  Could engrave rivers as lines on appropriate layers, or cut lakes as
  insets filled with blue-painted/acrylic pieces. This is a nice-to-have
  but significantly complicates the pipeline.

### User Experience & Output

- **Q17: Preview before cutting.**
  Should the tool generate a 3D preview? Options: matplotlib 3D plot,
  browser-based WebGL viewer, or just a stacked 2D SVG with transparency.
  A stacked SVG is simplest and gives a quick sanity check.

- **Q18: Output file naming and metadata.**
  Each SVG needs to encode: layer number, elevation range, material
  thickness, scale. How? Filename convention + embedded SVG metadata?

- **Q19: Caching strategy for DEM data.**
  DEM downloads can be large and slow. Should we cache the raw raster,
  the clipped raster, or the generated contours? All three? Where?

## Decisions Needed Before Implementation

| Decision | Options | Blocked By |
|---|---|---|
| Primary data source | 3DEP vs SRTM vs OpenTopography | Q1 testing |
| Contour algorithm | contourf vs gdal vs rasterize | Q4 testing |
| CLI framework | click vs typer | Personal preference |
| Alignment default | dowel holes vs engraved outlines | Q11 user input |
| SVG color convention | Red/blue/green vs layers | Q10 research |

## Acceptance Criteria

- [ ] Given a bounding box, produces a set of SVGs
- [ ] SVGs load cleanly in LightBurn/Glowforge/Inkscape
- [ ] Cut layers stack to produce recognizable terrain
- [ ] Alignment features produce <1mm registration error
- [ ] Pipeline runs in under 60s for a typical mountain
- [ ] Works for at least one non-US location (SRTM data)
