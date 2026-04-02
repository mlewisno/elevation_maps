---
title: "2D Rendered Preview for AI Agent Validation"
status: Captured
created: 2026-04-01
source: user
---

# IDEA-011: 2D Rendered Preview for AI Agent Validation

## Problem

The 3D matplotlib preview (`--render`) is useful for human inspection but
cannot be consumed by AI agents like Claude Code. When making changes to
contour generation, SVG output, or layer logic, there's no way for an AI
agent to visually verify the output looks correct — it can only check that
files were created, not that they look right.

A flat 2D rendered PNG with color-coded layers would be readable by
multimodal AI models, enabling a feedback loop where the agent can generate
a map, look at the preview, and identify issues (missing layers, broken
polygons, incorrect coastlines, etc.) without human intervention.

## Proposed Solution

Add a `--render-2d` flag that generates a top-down 2D PNG showing all
contour layers with distinct colors, similar to how the SVG looks but as
a raster image that AI agents can read.

- Render each layer as filled polygons (not just strokes)
- Use a clear color gradient: blues for water, greens/browns for land
- Include layer boundaries visible through slight color differences
- Output at sufficient resolution for AI model inspection (~1200px wide)
- Optionally include a legend showing layer elevation ranges

## Value Signal

- Enables AI-assisted development loop: change code → generate → inspect → fix
- Reduces reliance on human visual review for every pipeline change
- Could be integrated into CI or test workflows for regression detection
