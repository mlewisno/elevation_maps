"""Merge high-resolution land data with ETOPO bathymetry."""

import logging
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject

logger = logging.getLogger(__name__)


def merge_land_and_ocean(
    etopo_path: Path,
    land_path: Path,
    output_path: Path,
) -> Path:
    """Merge high-res land elevation over ETOPO ocean bathymetry.

    Uses land_path data where elevation > 0, ETOPO data where <= 0.
    The land raster is reprojected/resampled to match the land raster's
    grid (higher resolution).

    Returns path to the merged GeoTIFF.
    """
    with rasterio.open(land_path) as land_src:
        land_data = land_src.read(1)
        land_profile = land_src.profile.copy()
        land_transform = land_src.transform
        land_crs = land_src.crs
        land_shape = land_data.shape

    # Reproject ETOPO to match land raster grid
    etopo_resampled = np.empty(land_shape, dtype=np.float32)
    with rasterio.open(etopo_path) as etopo_src:
        reproject(
            source=rasterio.band(etopo_src, 1),
            destination=etopo_resampled,
            dst_transform=land_transform,
            dst_crs=land_crs,
            resampling=Resampling.bilinear,
        )

    # Merge: use land data where > 0, ETOPO where <= 0
    # Buffer slightly: use land data where land > -5m to avoid coastline gaps
    land_mask = land_data > -5.0
    merged = np.where(land_mask, land_data, etopo_resampled)

    # Write merged result
    land_profile.update(dtype=np.float32, count=1)
    with rasterio.open(output_path, "w", **land_profile) as dst:
        dst.write(merged.astype(np.float32), 1)
        dst.update_tags(description="Merged 3DEP land + ETOPO ocean elevation")

    logger.info(
        "Merged raster: %d x %d pixels, %.0fm to %.0fm",
        merged.shape[1],
        merged.shape[0],
        float(np.nanmin(merged)),
        float(np.nanmax(merged)),
    )
    return output_path
