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
    land_mask_path: Path | None = None,
) -> gpd.GeoDataFrame:
    """Generate contour band polygons from a DEM raster.

    Each layer represents the elevation band visible from above when
    layers are stacked. The bottom layer (index 0) is a full rectangle
    (the base piece). All other layers show only the area between their
    threshold and the next layer's threshold — the ring that would be
    exposed when looking down at the assembled map.

    If land_mask_path is provided (e.g., a 3DEP raster), land layer
    masks are intersected with its valid-data pixels to clip to actual
    coastlines rather than including shallow ocean shelf.

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

    # Load land mask from high-res source if available
    land_mask = None
    if land_mask_path is not None and land_mask_path.exists():
        with rasterio.open(land_mask_path) as lm_src:
            lm_data = lm_src.read(1)
            land_mask = (~np.isnan(lm_data)) & (lm_data > 1.0)
            logger.info(
                "Land mask loaded: %d land pixels (%.1f%%)",
                land_mask.sum(),
                land_mask.sum() / land_mask.size * 100,
            )

    total_pixels = elevation.size
    min_area_pixels = total_pixels * min_area_fraction

    breakpoints = layer_config.breakpoints()
    records = []

    for i in range(layer_config.layer_count):
        threshold = breakpoints[i]
        info = layer_config.layer_info(i)

        if i == 0:
            # Bottom layer: full rectangle (base piece)
            mask = np.ones_like(elevation, dtype=np.uint8)
        elif info["type"] == "water" and i < layer_config.layer_count - 1:
            # Water layers: band shape (area between this and next threshold)
            # Shows the ocean floor contour visible from above
            above_this = elevation >= threshold
            next_threshold = breakpoints[i + 1]
            above_next = elevation >= next_threshold
            mask = (above_this & ~above_next).astype(np.uint8)
        else:
            # Land layers: cumulative (everything >= threshold)
            # Shows the island/terrain shape at this elevation
            above = elevation >= threshold
            if land_mask is not None:
                above = above & land_mask
            mask = above.astype(np.uint8)

        if mask.sum() == 0:
            logger.debug("Layer %d: no pixels in band, skipping", i, threshold)
            continue

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
