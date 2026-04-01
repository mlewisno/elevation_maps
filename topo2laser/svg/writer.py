"""Generate multi-layer SVG for laser cutting."""

import logging
from pathlib import Path

import geopandas as gpd
import svgwrite

from topo2laser.svg.paths import lines_to_svg_ds, multipolygon_to_svg_ds

logger = logging.getLogger(__name__)

# Default color scheme
CUT_COLOR = "#FF0000"
ENGRAVE_ALIGN_COLOR = "#0000FF"
ENGRAVE_LABEL_COLOR = "#000000"
STROKE_WIDTH = "0.01mm"


def write_svg(
    gdf: gpd.GeoDataFrame,
    alignment_outlines: dict[int, list],
    output_path: Path,
    width_mm: float,
    height_mm: float,
    frame_polygon=None,
    cut_color: str = CUT_COLOR,
    engrave_color: str = ENGRAVE_ALIGN_COLOR,
) -> Path:
    """Write a multi-layer SVG file for laser cutting.

    Args:
        gdf: GeoDataFrame with contour polygons (in mm coordinates).
        alignment_outlines: Dict of layer_index → list of boundary lines.
        output_path: Path to write the SVG file.
        width_mm: Total width in mm.
        height_mm: Total height in mm.
        frame_polygon: Optional frame polygon to include.
        cut_color: Stroke color for cut paths.
        engrave_color: Stroke color for alignment engrave paths.

    Returns:
        Path to the written SVG file.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Add margin for frame if present
    total_w = width_mm
    total_h = height_mm
    if frame_polygon:
        fb = frame_polygon.bounds
        total_w = fb[2] - fb[0]
        total_h = fb[3] - fb[1]
        offset_x = -fb[0]
        offset_y = -fb[1]
    else:
        offset_x = 0.0
        offset_y = 0.0

    dwg = svgwrite.Drawing(
        str(output_path),
        size=(f"{total_w:.2f}mm", f"{total_h:.2f}mm"),
        viewBox=f"0 0 {total_w:.2f} {total_h:.2f}",
    )
    dwg.add(svgwrite.base.Title("topo2laser output"))

    sorted_layers = sorted(gdf["layer"].unique())

    for layer_idx in sorted_layers:
        row = gdf[gdf["layer"] == layer_idx].iloc[0]
        layer_type = row["type"]
        emin = row["elevation_min"]
        emax = row["elevation_max"]

        group_id = (
            f"layer-{layer_idx:02d}-{layer_type}-{emin:.0f}m-to-{emax:.0f}m"
        ).replace("--", "-neg")

        group = dwg.g(id=group_id)

        # Cut paths (red)
        cut_ds = multipolygon_to_svg_ds(row.geometry, flip_y=height_mm)
        for d in cut_ds:
            # Translate for frame offset
            group.add(
                dwg.path(
                    d=d,
                    stroke=cut_color,
                    stroke_width=STROKE_WIDTH,
                    fill="none",
                    transform=f"translate({offset_x:.3f},{offset_y:.3f})",
                )
            )

        # Alignment engrave paths (blue)
        if layer_idx in alignment_outlines:
            outline_ds = lines_to_svg_ds(
                alignment_outlines[layer_idx], flip_y=height_mm
            )
            for d in outline_ds:
                group.add(
                    dwg.path(
                        d=d,
                        stroke=engrave_color,
                        stroke_width=STROKE_WIDTH,
                        fill="none",
                        transform=f"translate({offset_x:.3f},{offset_y:.3f})",
                    )
                )

        dwg.add(group)

    # Frame piece (if requested)
    if frame_polygon:
        frame_group = dwg.g(id="frame")
        frame_ds = multipolygon_to_svg_ds(frame_polygon, flip_y=total_h)
        for d in frame_ds:
            frame_group.add(
                dwg.path(
                    d=d,
                    stroke=cut_color,
                    stroke_width=STROKE_WIDTH,
                    fill="none",
                    transform=f"translate({offset_x:.3f},{offset_y:.3f})",
                )
            )
        dwg.add(frame_group)

    dwg.save()
    logger.info("SVG written to %s (%.1fmm x %.1fmm)", output_path, total_w, total_h)
    return output_path
