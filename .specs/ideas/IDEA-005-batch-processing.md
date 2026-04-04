---
title: "Batch Processing from Config File"
status: Considering
created: 2026-03-31
source: vision
ice_scores:
  impact: 5
  confidence: 8
  ease: 6
  total: 240
---

# IDEA-005: Batch Processing from Config File

Accept a YAML/TOML config file defining multiple maps to generate in one run.
Useful for producing a product line of maps for different locations with
consistent settings.

```yaml
defaults:
  material_thickness: 3mm
  total_height: 36mm
  frame: true
  kerf: 0.2mm

maps:
  - name: kauai
    bbox: "21.71,-160.5,22.3,-159.2"
    labels: ["Līhu'e", "Waimea", "Hanalei"]
  - name: duluth
    bbox: "46.7,-92.2,46.85,-91.9"
    labels: ["Duluth", "Superior"]
```
