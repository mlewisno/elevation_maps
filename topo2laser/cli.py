"""CLI entry point for topo2laser."""

import logging
from pathlib import Path

import click

from topo2laser.contours.layer_calculator import resolve_thickness
from topo2laser.elevation import BoundingBox
from topo2laser.pipeline import PipelineConfig, run


def _parse_mm(value: str | None) -> float | None:
    """Parse a mm value like '300mm' or '300' to float, or None."""
    if value is None:
        return None
    return float(value.rstrip("mm").strip())


@click.command()
@click.option(
    "--bbox",
    required=True,
    help="Bounding box as 'south,west,north,east' in decimal degrees.",
)
@click.option(
    "--output",
    "-o",
    required=True,
    type=click.Path(),
    help="Output directory for SVG file.",
)
@click.option(
    "--material-thickness",
    default="thin-ply",
    help="Material thickness: mm value or preset name.",
)
@click.option(
    "--layers",
    default=None,
    type=int,
    help="Number of layers (alternative to --total-height).",
)
@click.option(
    "--total-height",
    default=None,
    help="Total map height in mm (alternative to --layers).",
)
@click.option("--width", default=None, help="Target width in mm (default: fit to bed).")
@click.option(
    "--height", default=None, help="Target height in mm (auto from aspect ratio)."
)
@click.option("--kerf", default="0.2mm", help="Laser kerf width in mm.")
@click.option(
    "--bathymetry/--no-bathymetry",
    default=True,
    help="Include ocean depth data.",
)
@click.option(
    "--high-res/--no-high-res",
    default=False,
    help="Use 3DEP 10m land data (US only, slower first run).",
)
@click.option(
    "--frame/--no-frame",
    default=True,
    help="Generate rectangular frame piece.",
)
@click.option(
    "--frame-border",
    default="15mm",
    help="Frame border width in mm.",
)
@click.option(
    "--smooth-iterations",
    default=3,
    type=int,
    help="Chaikin smoothing passes (0 to disable).",
)
@click.option(
    "--simplify-tolerance",
    default="0.5mm",
    help="Douglas-Peucker simplification tolerance in mm.",
)
@click.option(
    "--min-polygon",
    default="5mm",
    help="Drop polygons smaller than this in mm (0 to keep all).",
)
@click.option(
    "--max-water-layers",
    default=4,
    type=int,
    help="Max layers for ocean depth (rest go to land). 0 = uniform.",
)
@click.option("-v", "--verbose", is_flag=True, help="Show detailed logging.")
def main(
    bbox,
    output,
    material_thickness,
    layers,
    total_height,
    width,
    height,
    kerf,
    bathymetry,
    frame,
    frame_border,
    smooth_iterations,
    simplify_tolerance,
    min_polygon,
    max_water_layers,
    high_res,
    verbose,
):
    """Convert geographic elevation data to laser-cuttable SVG layers."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    try:
        parsed_bbox = BoundingBox.from_string(bbox)
    except ValueError as e:
        raise click.BadParameter(str(e), param_hint="--bbox") from e

    config = PipelineConfig(
        bbox=parsed_bbox,
        output_dir=Path(output),
        material_thickness_mm=resolve_thickness(material_thickness),
        total_height_mm=_parse_mm(total_height),
        layer_count=layers,
        width_mm=_parse_mm(width),
        height_mm=_parse_mm(height),
        kerf_mm=_parse_mm(kerf) or 0.2,
        include_bathymetry=bathymetry,
        high_res_land=high_res,
        min_polygon_mm=_parse_mm(min_polygon) or 5.0,
        max_water_layers=max_water_layers,
        include_frame=frame,
        frame_border_mm=_parse_mm(frame_border) or 15.0,
        smooth_iterations=smooth_iterations,
        simplify_tolerance_mm=_parse_mm(simplify_tolerance) or 0.5,
    )

    result = run(config)
    click.echo(f"\nSVG written to: {result}")


if __name__ == "__main__":
    main()
