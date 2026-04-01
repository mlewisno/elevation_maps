---
title: "Auto-Detect Data Source by Region"
status: Considering
created: 2026-03-31
source: vision
ice_scores:
  impact: 7
  confidence: 8
  ease: 7
  total: 392
---

# IDEA-007: Auto-Detect Data Source by Region

Automatically select the best elevation data source based on the bounding
box location. US locations → 3DEP for land + ETOPO for ocean. Non-US →
Copernicus GLO-30 for land + ETOPO for ocean. Could also detect if
high-res lidar data is available from OpenTopography.
