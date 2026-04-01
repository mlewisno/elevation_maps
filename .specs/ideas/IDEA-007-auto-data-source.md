---
title: "Auto-Detect Data Source by Region"
status: Captured
created: 2026-03-31
source: vision
---

# IDEA-007: Auto-Detect Data Source by Region

Automatically select the best elevation data source based on the bounding
box location. US locations → 3DEP for land + ETOPO for ocean. Non-US →
Copernicus GLO-30 for land + ETOPO for ocean. Could also detect if
high-res lidar data is available from OpenTopography.
