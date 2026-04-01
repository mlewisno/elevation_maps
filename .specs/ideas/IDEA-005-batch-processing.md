---
title: "Batch Processing from Config File"
status: Captured
created: 2026-03-31
source: vision
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
    bbox: "21.8,-160.3,22.3,-159.2"
    labels: ["Līhu'e", "Waimea", "Hanalei"]
  - name: duluth
    bbox: "46.7,-92.2,46.85,-91.9"
    labels: ["Duluth", "Superior"]
```
