"""Pipeline orchestration — connects all stages."""

import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import rasterio

from topo2laser.alignment import generate_alignment_outlines, generate_frame
from topo2laser.contours import calculate_layers, generate_contours
from topo2laser.contours.simplify import simplify_contours
from topo2laser.elevation import BoundingBox, fetch_elevation
from topo2laser.svg import project_and_scale, write_svg
from topo2laser.svg.writer import write_per_layer_svgs

logger = logging.getLogger(__name__)


@dataclass
class PipelineConfig:
    """Configuration for a full pipeline run."""

    bbox: BoundingBox
    output_dir: Path
    material_thickness_mm: float = 3.0
    total_height_mm: float | None = None
    layer_count: int | None = None
    width_mm: float | None = None
    height_mm: float | None = None
    kerf_mm: float = 0.2
    include_bathymetry: bool = True
    include_frame: bool = True
    frame_border_mm: float = 15.0
    smooth_iterations: int = 3
    simplify_tolerance_mm: float = 0.5
    min_polygon_mm: float = 5.0
    max_water_layers: int = 4

    def __post_init__(self):
        if self.total_height_mm is None and self.layer_count is None:
            self.layer_count = 10  # default


def run(config: PipelineConfig) -> Path:
    """Execute the full pipeline. Returns path to the output SVG."""
    # Stage 1: Fetch elevation data
    logger.info("Stage 1: Fetching elevation data...")
    raster_path = fetch_elevation(
        config.bbox,
        include_bathymetry=config.include_bathymetry,
    )

    # Read elevation range from raster
    with rasterio.open(raster_path) as src:
        data = src.read(1)
        valid = data[~np.isnan(data)]
        elevation_min = float(valid.min())
        elevation_max = float(valid.max())

    logger.info("Elevation range: %.0fm to %.0fm", elevation_min, elevation_max)

    # Stage 2: Generate contours
    logger.info("Stage 2: Generating contour polygons...")
    layer_config = calculate_layers(
        elevation_min=elevation_min,
        elevation_max=elevation_max,
        material_thickness_mm=config.material_thickness_mm,
        total_height_mm=config.total_height_mm,
        layer_count=config.layer_count,
        max_water_layers=config.max_water_layers,
    )
    logger.info(
        "Layer config: %d layers, %.1fmm total height",
        layer_config.layer_count,
        layer_config.total_height_mm,
    )

    gdf = generate_contours(raster_path, layer_config)

    # Stage 3: Project and scale to mm
    logger.info("Stage 3: Projecting and scaling to mm...")
    gdf, dims = project_and_scale(
        gdf,
        center_lat=config.bbox.center_lat,
        center_lon=config.bbox.center_lon,
        target_width_mm=config.width_mm,
        target_height_mm=config.height_mm,
    )

    # Stage 3b: Smooth, simplify, and filter small polygons
    logger.info("Stage 3b: Smoothing and filtering contours...")
    gdf = simplify_contours(
        gdf,
        tolerance=config.simplify_tolerance_mm,
        smooth_iterations=config.smooth_iterations,
        min_polygon_mm=config.min_polygon_mm,
    )

    # Stage 3c: Generate alignment outlines
    logger.info("Stage 3c: Generating alignment outlines...")
    alignment_outlines = generate_alignment_outlines(gdf)

    # Stage 3d: Generate frame (optional)
    frame_polygon = None
    if config.include_frame:
        logger.info("Stage 3d: Generating frame...")
        frame_polygon = generate_frame(
            dims.width_mm,
            dims.height_mm,
            border_mm=config.frame_border_mm,
        )

    # Stage 4: Write SVGs
    logger.info("Stage 4: Writing combined SVG...")
    output_path = config.output_dir / "topo_map.svg"
    write_svg(
        gdf=gdf,
        alignment_outlines=alignment_outlines,
        output_path=output_path,
        width_mm=dims.width_mm,
        height_mm=dims.height_mm,
        frame_polygon=frame_polygon,
    )

    logger.info("Stage 4b: Writing per-layer SVGs...")
    write_per_layer_svgs(
        gdf=gdf,
        alignment_outlines=alignment_outlines,
        output_dir=config.output_dir,
        width_mm=dims.width_mm,
        height_mm=dims.height_mm,
        frame_polygon=frame_polygon,
    )

    # Print summary
    _print_summary(gdf, layer_config, dims, output_path)

    return output_path


def _print_summary(gdf, layer_config, dims, output_path):
    """Print a human-readable summary of the output."""
    print(f"\n{'=' * 50}")
    print("topo2laser output summary")
    print(f"{'=' * 50}")
    print(f"Output: {output_path}")
    print(f"Dimensions: {dims.width_mm:.1f}mm x {dims.height_mm:.1f}mm")
    print(
        f"Layers: {layer_config.layer_count} "
        f"({layer_config.material_thickness_mm}mm each, "
        f"{layer_config.total_height_mm:.1f}mm total)"
    )
    print("\nLayer breakdown:")
    for _, row in gdf.iterrows():
        n_polys = len(row.geometry.geoms) if hasattr(row.geometry, "geoms") else 1
        print(
            f"  Layer {row['layer']:2d}: {row['elevation_min']:7.0f}m to "
            f"{row['elevation_max']:7.0f}m  [{row['type']:5s}]  "
            f"({n_polys} polygon{'s' if n_polys > 1 else ''})"
        )
    if dims.exceeds_bed:
        print("\n⚠ WARNING: Output exceeds xTool P2 bed (600mm x 305mm)")
    print(f"{'=' * 50}\n")
