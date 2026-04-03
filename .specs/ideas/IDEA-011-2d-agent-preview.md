---
title: "2D Rendered Preview for AI Agent Validation"
status: Promoted
created: 2026-04-01
source: user
promoted_to: FEAT-012
ice_scores:
  impact: 9
  confidence: 9
  ease: 8
  total: 648
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

## Prioritization Notes (2026-04-02)

ICE 648 (I:9 C:9 E:8). Promoted to FEAT-012. High impact because it
unlocks AI-driven development feedback loops — Claude Code can read the
PNG and validate output visually. High confidence because matplotlib 2D
rendering is straightforward. High ease because we already have the
layer data and coloring logic from the 3D renderer.
