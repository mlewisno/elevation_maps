"""Generate contour polygons from elevation raster data."""

import logging
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
import rasterio.features
from shapely.geometry import MultiPolygon, Polygon, shape
from shapely.validation import make_valid

from topo2laser.contours.layer_calculator import LayerConfig

logger = logging.getLogger(__name__)

# Minimum polygon area as fraction of total raster area
MIN_AREA_FRACTION = 0.0005


def generate_contours(
    raster_path: Path,
    layer_config: LayerConfig,
    min_area_fraction: float = MIN_AREA_FRACTION,
) -> gpd.GeoDataFrame:
    """Generate contour polygons from a DEM raster.

    For each layer, creates a polygon representing all areas at or above
    that layer's minimum elevation. This produces the shape that would be
    cut for that physical layer.

    Returns a GeoDataFrame with columns:
        - layer: layer index (0 = bottom/deepest)
        - elevation_min: lower bound of this layer's elevation band
        - elevation_max: upper bound
        - type: 'water', 'land', or 'mixed'
        - geometry: the polygon(s) for this layer
    """
    with rasterio.open(raster_path) as src:
        elevation = src.read(1)
        transform = src.transform
        crs = src.crs

    # Calculate total raster area for minimum area filtering
    total_pixels = elevation.size
    min_area_pixels = total_pixels * min_area_fraction

    breakpoints = layer_config.breakpoints()
    records = []

    for i in range(layer_config.layer_count):
        threshold = breakpoints[i]
        info = layer_config.layer_info(i)

        # Create binary mask: 1 where elevation >= threshold
        mask = (elevation >= threshold).astype(np.uint8)

        if mask.sum() == 0:
            logger.debug("Layer %d: no pixels above %.1fm, skipping", i, threshold)
            continue

        # Vectorize the mask into polygons
        polygons = _vectorize_mask(mask, transform, min_area_pixels)

        if polygons is None:
            logger.debug("Layer %d: no valid polygons after filtering", i)
            continue

        records.append(
            {
                "layer": i,
                "elevation_min": info["elevation_min"],
                "elevation_max": info["elevation_max"],
                "type": info["type"],
                "geometry": polygons,
            }
        )
        logger.info(
            "Layer %d (%.0fm to %.0fm, %s): %d polygon(s)",
            i,
            info["elevation_min"],
            info["elevation_max"],
            info["type"],
            len(polygons.geoms) if hasattr(polygons, "geoms") else 1,
        )

    if not records:
        raise RuntimeError("No contour polygons generated — check raster data")

    gdf = gpd.GeoDataFrame(records, crs=crs)
    logger.info("Generated %d contour layers", len(gdf))
    return gdf


def _vectorize_mask(
    mask: np.ndarray,
    transform: rasterio.Affine,
    min_area_pixels: float,
) -> Polygon | MultiPolygon | None:
    """Convert a binary mask to shapely polygon(s).

    Filters out polygons smaller than min_area_pixels and fixes
    invalid geometries.
    """
    shapes = list(rasterio.features.shapes(mask, mask=mask, transform=transform))

    if not shapes:
        return None

    polygons = []
    for geom, value in shapes:
        if value != 1:
            continue
        poly = shape(geom)
        poly = make_valid(poly)
        if poly.is_empty:
            continue
        # Filter by area (in CRS units — degrees for EPSG:4326)
        # We compare pixel counts via the mask, so use a proportional check
        if poly.area < min_area_pixels * abs(transform.a * transform.e):
            continue
        polygons.append(poly)

    if not polygons:
        return None

    if len(polygons) == 1:
        return polygons[0]
    return MultiPolygon(polygons)
