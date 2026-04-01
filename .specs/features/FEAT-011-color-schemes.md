---
title: "Configurable SVG Color Schemes"
status: Draft
created: 2026-04-01
epic: usability
promoted_from: IDEA-006
---

# FEAT-011: Configurable SVG Color Schemes

## Summary

Allow users to configure the SVG stroke colors used for cut, engrave, and
score operations, so the output matches their laser cutter software's
expected color-to-operation mapping.

## Requirements

### Functional

**Color Configuration**
- Accept `--color-cut`, `--color-engrave`, `--color-score` CLI flags
- Accept `--color-preset` for common laser software defaults
- Colors specified as hex values (e.g., `#FF0000`) or named colors

**Presets**
- `xtool` — current defaults (red cuts, blue engrave)
- `lightburn` — LightBurn defaults
- `glowforge` — Glowforge defaults
- Allow user to define custom presets via config file

**Layer Name Mapping**
- Some software uses SVG layer/group names instead of colors
- Support `--layer-naming` option to control group naming convention

### Non-Functional
- Current behavior (red/blue) remains the default
- Invalid color values produce a clear error message

## Technical Approach

1. Extract current hardcoded colors in `svg/writer.py` to a color scheme object
2. Add CLI flags and preset lookup
3. Pass color scheme through to SVG writer
4. Optionally load custom presets from a config file (`~/.topo2laser.yml`)

## Files to Create/Modify

- `topo2laser/svg/colors.py` — Color scheme definitions and presets
- `topo2laser/svg/writer.py` — Use color scheme instead of constants
- `topo2laser/cli.py` — Add color flags
- `tests/test_colors.py` — Unit tests

## Acceptance Criteria

- [ ] `--color-cut "#0000FF"` changes cut paths to blue
- [ ] `--color-preset lightburn` applies LightBurn color conventions
- [ ] Default behavior unchanged (red cuts, blue engrave)
- [ ] Invalid color values produce helpful error message
- [ ] SVG output uses configured colors throughout
