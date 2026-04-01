---
title: "Location Name to Bounding Box Lookup"
status: Captured
created: 2026-03-31
source: user
---

# IDEA-009: Location Name to Bounding Box Lookup

Allow users to specify a location by name instead of raw coordinates.

```bash
topo2laser --location "Kaua'i, Hawaii" -o output/kauai
topo2laser --location "Duluth, MN" --radius 15km -o output/duluth
```

**Approach options**:
- Nominatim (OSM geocoding) — free, no API key, returns bounding boxes
- `geopy` Python library wraps multiple geocoding services
- Could cache lookups to avoid repeated API calls

**Concerns**:
- Bounding box from geocoding may not match what the user actually wants
  (city boundary vs. surrounding area, island vs. island + ocean shelf)
- Would need a `--radius` or `--padding` option to expand the bbox
- Rate limiting on free geocoding services
