# topo2laser

Convert geographic elevation data into layered SVGs for laser cutting topographic relief maps. Each layer is cut from sheet material and stacked to produce a physical 3D terrain model.

## Setup

```bash
uv sync --extra dev
```

## Quick Start

```bash
# Kaua'i + Ni'ihau (ocean + islands)
uv run topo2laser \
  --bbox "21.71,-160.5,22.3,-159.2" \
  -o output/kauai \
  --material-thickness thin-ply \
  --high-res \
  --render-2d

# Duluth / Lake Superior (lake + terrain, water surface at 183m)
uv run topo2laser \
  --bbox "46.58,-92.35,46.95,-91.75" \
  -o output/duluth \
  --water-level 183 \
  --water-layers 4 \
  --layers 10 \
  --render-2d

# Grand Canyon (all-land, 12 layers)
uv run topo2laser \
  --bbox "36.0,-112.3,36.25,-111.9" \
  -o output/grand-canyon \
  --high-res \
  --layers 12 \
  --render-2d
```

## Output

```
output/kauai/
  topo_map.svg              # Combined multi-layer SVG
  render_2d.png             # Top-down color preview
  render.png                # 3D perspective preview (with --render)
  layers/
    layer-00-water.svg      # Per-layer SVGs for individual cutting
    layer-01-water.svg
    ...
    layer-09-land.svg
    frame.svg               # Rectangular frame piece
```

## Key Options

| Option | Description |
|--------|-------------|
| `--bbox` | Bounding box: `"south,west,north,east"` |
| `--material-thickness` | `thin-ply` (3mm), `cardstock` (1.5mm), `thick-ply` (6mm), or mm value |
| `--layers` | Total layer count (default 10) |
| `--water-layers` / `--land-layers` | Explicit water/land layer split |
| `--water-level` | Water surface elevation in meters (0 = sea level, 183 = Lake Superior) |
| `--high-res` | Use 3DEP 10m data for US locations (slower first run) |
| `--width` / `--height` | Target dimensions in mm (default: fit xTool P2 bed) |
| `--render-2d` | Generate top-down 2D preview PNG |
| `--render` | Generate 3D perspective preview PNG |
| `--render-interactive` | Open rotatable 3D preview window |

## Data Sources

- **Ocean bathymetry**: ETOPO 2022 (15 arcsecond, global)
- **Land elevation**: USGS 3DEP (10m, US only, via `--high-res`)
- **Lake bathymetry**: ETOPO + `--water-level` for Great Lakes

## Development

```bash
uv run pytest                    # Run tests
uv run black topo2laser/ tests/  # Format
uv run ruff check --fix topo2laser/ tests/  # Lint

# Regenerate reference images (4 test locations)
./scripts/generate-reference.sh

# Run visual regression check
uv run python scripts/visual-regression-check.py --all
```

## Using with Claude Code

Claude Code can read the 2D preview PNGs to visually validate pipeline output. Generate a render and ask Claude to inspect it:

```bash
uv run topo2laser --bbox "..." -o output/test --render-2d
# Then in Claude Code: "Read output/test/render_2d.png and check for issues"
```

Reference images in `tests/reference/` provide baselines for 4 use cases:
- **kauai** — Ocean + islands (bathymetry)
- **duluth** — Lake + terrain (water-level)
- **grand-canyon** — All-land, dramatic terrain
- **camp-woodbrooke** — All-land, small scale (~500 acres)

The visual regression validator runs automatically on `git push` when pipeline files change, comparing generated renders against these references using SSIM.
