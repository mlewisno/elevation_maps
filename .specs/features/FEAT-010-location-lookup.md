---
title: "Location Name to Bounding Box Lookup"
status: Draft
created: 2026-04-01
epic: usability
promoted_from: IDEA-009
---

# FEAT-010: Location Name to Bounding Box Lookup

## Summary

Allow users to specify a location by name instead of raw bounding box
coordinates. Uses geocoding to resolve the name to a bounding box, with
optional radius/padding control.

## Requirements

### Functional

**Location Lookup**
- Accept `--location "Kaua'i, Hawaii"` as alternative to `--bbox`
- Use Nominatim (OSM geocoding) via `geopy` to resolve name to bbox
- Return the feature's bounding box (island boundary, city boundary, etc.)
- Support `--radius` to override the returned bbox with a circular area
  centered on the location (e.g., `--radius 15km`)
- Support `--padding` to expand the returned bbox by a percentage or distance

**Disambiguation**
- If multiple results match, show the top 3-5 and ask the user to pick
  or refine the query
- Show the resolved bbox so the user knows what they're getting

**Caching**
- Cache geocoding results to avoid repeated API calls
- Store in the same cache directory as elevation data

### Non-Functional
- `--location` and `--bbox` are mutually exclusive
- Respect Nominatim usage policy (1 request/second, identify user agent)
- Graceful fallback if geocoding service is unavailable

## Technical Approach

1. Add `geopy` dependency with Nominatim geocoder
2. Parse `--location` argument, call geocoder
3. Extract bounding box from response, apply padding/radius if specified
4. Pass resolved bbox to existing elevation pipeline
5. Cache results keyed on query string

## Files to Create/Modify

- `topo2laser/geocode.py` — Location lookup and caching
- `topo2laser/cli.py` — Add `--location`, `--radius`, `--padding` flags
- `topo2laser/pipeline.py` — Resolve location before elevation fetch
- `tests/test_geocode.py` — Unit tests

## Open Questions

- **Interaction model**: Simple geocoding may not give the user enough control
  over bounds. The real workflow involves deciding canvas ratio, how much
  surrounding area to include, and how the feature sits in the frame. Options:
  1. Multi-step interactive CLI — geocode, show bbox on a map preview, let
     user adjust before committing to the full pipeline
  2. Research existing tools with visual/drag-and-drop area selection that
     could output coordinates for our pipeline
  3. Keep simple geocoding as a starting point, but lean on `--render` from
     FEAT-009 for quick iteration (geocode → render → adjust padding → repeat)
- Should we research what tools already exist for visual bbox selection before
  building our own?

## Acceptance Criteria

- [ ] `--location "Kaua'i"` resolves to a valid bounding box
- [ ] `--radius 15km` overrides bbox with circular area
- [ ] `--padding 10%` expands the resolved bbox
- [ ] Multiple matches prompt user to choose
- [ ] Second lookup for same query uses cache
- [ ] `--location` and `--bbox` cannot be used together
