"""Project and scale geographic coordinates to physical mm dimensions."""

import logging
from dataclasses import dataclass

import geopandas as gpd
import pyproj

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
) -> tuple[gpd.GeoDataFrame, PhysicalDimensions]:
    """Project to LAEA and scale coordinates from meters to mm.

    If neither target_width_mm nor target_height_mm is given, scales to
    fit the xTool P2 bed (600mm x 305mm) while preserving aspect ratio.

    Returns the transformed GeoDataFrame and physical dimensions.
    """
    crs = laea_crs(center_lat, center_lon)
    projected = gdf.to_crs(crs)

    bounds = projected.total_bounds  # minx, miny, maxx, maxy
    extent_x = bounds[2] - bounds[0]  # meters
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

    # Translate to origin (min corner at 0,0)
    new_bounds = scaled.total_bounds
    dx = -new_bounds[0]
    dy = -new_bounds[1]
    scaled["geometry"] = scaled["geometry"].translate(xoff=dx, yoff=dy)

    final_bounds = scaled.total_bounds
    dims = PhysicalDimensions(
        width_mm=float(final_bounds[2] - final_bounds[0]),
        height_mm=float(final_bounds[3] - final_bounds[1]),
        scale_factor=scale,
    )

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
