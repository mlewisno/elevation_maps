---
title: "Labels and Decorative Elements"
status: Draft
created: 2026-03-31
epic: enhancements
vision: FEAT-001
depends_on: [FEAT-005]
---

# FEAT-006: Labels and Decorative Elements

## Summary

Add engraved text labels (place names, elevation markers) and optional
decorative elements (user logo) to the SVG output. All text is converted to
SVG paths since laser cutters don't render fonts.

## Requirements

### Functional

**User-Provided Label List**
- Accept a list of place names via CLI (`--labels "Līhu'e,Waimea,Hanalei"`)
- Query OSM Overpass API to find coordinates for each name within the bbox
- Place each label on the appropriate layer based on the location's elevation
- Engrave the place name as a path on that layer's surface
- Handle names with diacritics (Hawaiian, etc.)

**Town Labels by Population**
- Accept `--label-towns-above N` to auto-label towns with population >= N
- Query OSM for `place=city|town|village` nodes with population tags
- Filter by population threshold
- Place on appropriate layers

**Elevation Labels**
- Optionally engrave elevation values on layer edges/faces
- Show the elevation range for each layer

**User Logo**
- Accept `--logo path/to/logo.svg`
- Place in a configurable corner of the top layer or frame
- Scale to a sensible size relative to the map

**Text-to-Path**
- All text must be converted to SVG path outlines
- Use a bundled or system font (clean sans-serif default)
- Font size scales with map dimensions

### Non-Functional
- OSM queries should be cached to avoid repeated API calls
- Label placement should avoid overlapping other labels

## Technical Approach

1. Query OSM Overpass API with `requests` for named places in bbox
2. Match place coordinates to the correct layer by elevation
3. Convert text to SVG paths using a font renderer (options: `fonttools` +
   `svgpathtools`, or pre-rendered SVG text outlines, or Inkscape CLI)
4. Position label paths on the correct layer group in the SVG
5. Load user logo SVG and embed as a group, scaled and positioned

## Files to Create/Modify

- `topo2laser/landmarks/query.py` — OSM Overpass queries
- `topo2laser/landmarks/placement.py` — Label-to-layer assignment
- `topo2laser/svg/text.py` — Text-to-path conversion
- `topo2laser/svg/logo.py` — Logo SVG embedding
- `tests/test_landmarks.py` — Unit tests

## Open Questions

- Q7 from vision: Which font for engraving? Need one that looks good
  at small sizes when laser-engraved on wood.
- Text-to-path approach: `fonttools` vs Inkscape CLI vs bundled outlines?
- Label collision detection: simple bounding box check vs more sophisticated?

## Acceptance Criteria

- [ ] User-provided place names appear on correct layers
- [ ] Hawaiian diacritics render correctly (Līhu'e, Po'ipū, etc.)
- [ ] Labels are SVG paths, not text elements
- [ ] Towns above population threshold are auto-labeled
- [ ] User logo appears in specified corner
- [ ] Labels don't overlap each other (basic collision avoidance)
