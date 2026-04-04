"""Project and scale geographic coordinates to physical mm dimensions."""

import logging
from dataclasses import dataclass

import geopandas as gpd
import pyproj
from shapely.geometry import box
from shapely.validation import make_valid

logger = logging.getLogger(__name__)

MAX_BED_WIDTH_MM = 600.0
MAX_BED_HEIGHT_MM = 305.0


@dataclass
class PhysicalDimensions:
    """Physical output dimensions in mm."""

    width_mm: float
    height_mm: float
    scale_factor: float  # mm per CRS unit

    @property
    def exceeds_bed(self) -> bool:
        return self.width_mm > MAX_BED_WIDTH_MM or self.height_mm > MAX_BED_HEIGHT_MM


def laea_crs(center_lat: float, center_lon: float) -> pyproj.CRS:
    """Create a Lambert Azimuthal Equal Area CRS centered on a point."""
    return pyproj.CRS(
        proj="laea",
        lat_0=center_lat,
        lon_0=center_lon,
        x_0=0,
        y_0=0,
        datum="WGS84",
        units="m",
    )


def project_and_scale(
    gdf: gpd.GeoDataFrame,
    center_lat: float,
    center_lon: float,
    target_width_mm: float | None = None,
    target_height_mm: float | None = None,
    bbox_south: float | None = None,
    bbox_west: float | None = None,
    bbox_north: float | None = None,
    bbox_east: float | None = None,
) -> tuple[gpd.GeoDataFrame, PhysicalDimensions]:
    """Project to LAEA and scale coordinates from meters to mm.

    If bbox corners are provided, the clip rectangle is derived from the
    projected bbox (avoiding LAEA warp artifacts from raster-edge geometry).
    Otherwise falls back to using total_bounds.

    Returns the transformed GeoDataFrame and physical dimensions.
    """
    crs = laea_crs(center_lat, center_lon)
    projected = gdf.to_crs(crs)

    # Derive extent from projected bbox corners if available
    if all(v is not None for v in (bbox_south, bbox_west, bbox_north, bbox_east)):
        # Project corner points directly (not a polygon, which curves)
        transformer = pyproj.Transformer.from_crs("EPSG:4326", crs, always_xy=True)
        corners_x, corners_y = transformer.transform(
            [bbox_west, bbox_east, bbox_west, bbox_east],
            [bbox_south, bbox_south, bbox_north, bbox_north],
        )
        bbox_bounds = [
            min(corners_x),
            min(corners_y),
            max(corners_x),
            max(corners_y),
        ]
        extent_x = bbox_bounds[2] - bbox_bounds[0]
        extent_y = bbox_bounds[3] - bbox_bounds[1]
    else:
        bbox_bounds = None
        bounds = projected.total_bounds
        extent_x = bounds[2] - bounds[0]
        extent_y = bounds[3] - bounds[1]

    if target_width_mm and target_height_mm:
        scale_x = target_width_mm / extent_x
        scale_y = target_height_mm / extent_y
        scale = min(scale_x, scale_y)
    elif target_width_mm:
        scale = target_width_mm / extent_x
    elif target_height_mm:
        scale = target_height_mm / extent_y
    else:
        scale_x = MAX_BED_WIDTH_MM / extent_x
        scale_y = MAX_BED_HEIGHT_MM / extent_y
        scale = min(scale_x, scale_y)

    # Scale geometries: multiply coordinates by scale factor (m → mm)
    scaled = projected.copy()
    scaled["geometry"] = scaled["geometry"].affine_transform([scale, 0, 0, scale, 0, 0])

    # Derive clip rectangle from projected bbox (clean rectangle)
    # rather than from geometry bounds (which include LAEA warp artifacts)
    if bbox_bounds is not None:
        cb = [c * scale for c in bbox_bounds]
    else:
        cb = list(scaled.total_bounds)
    clip_rect = box(cb[0], cb[1], cb[2], cb[3])

    # Clip all geometries to the clean rectangle
    scaled["geometry"] = scaled["geometry"].intersection(clip_rect)
    scaled["geometry"] = scaled["geometry"].apply(make_valid)

    # Translate so clip rect origin is at (0,0)
    dx = -cb[0]
    dy = -cb[1]
    scaled["geometry"] = scaled["geometry"].translate(xoff=dx, yoff=dy)

    width_mm = float(cb[2] - cb[0])
    height_mm = float(cb[3] - cb[1])
    dims = PhysicalDimensions(
        width_mm=width_mm,
        height_mm=height_mm,
        scale_factor=scale,
    )

    # Replace base layer (layer 0) with a clean output rectangle
    base_mask = scaled["layer"] == 0
    if base_mask.any():
        scaled.loc[base_mask, "geometry"] = box(0, 0, width_mm, height_mm)

    if dims.exceeds_bed:
        logger.warning(
            "Output (%.0fmm x %.0fmm) exceeds xTool P2 bed (%.0fmm x %.0fmm)",
            dims.width_mm,
            dims.height_mm,
            MAX_BED_WIDTH_MM,
            MAX_BED_HEIGHT_MM,
        )

    logger.info("Output dimensions: %.1fmm x %.1fmm", dims.width_mm, dims.height_mm)
    return scaled, dims
