"""Polygon simplification and smoothing for laser-cuttable output."""

import geopandas as gpd
import numpy as np
from shapely.geometry import MultiPolygon, Polygon
from shapely.validation import make_valid


def simplify_contours(
    gdf: gpd.GeoDataFrame,
    tolerance: float = 0.5,
    smooth_iterations: int = 3,
) -> gpd.GeoDataFrame:
    """Simplify and smooth contour polygons for cleaner laser cuts.

    First applies Chaikin corner-cutting to smooth staircase edges from
    raster vectorization, then Douglas-Peucker to reduce vertex count.

    Args:
        gdf: GeoDataFrame with contour polygons (in mm coordinates).
        tolerance: Douglas-Peucker tolerance in mm after smoothing.
        smooth_iterations: Number of Chaikin smoothing passes.

    Returns:
        GeoDataFrame with smoothed geometries.
    """
    result = gdf.copy()
    result["geometry"] = result["geometry"].apply(
        lambda geom: _smooth_geometry(geom, smooth_iterations)
    )
    if tolerance > 0:
        result["geometry"] = result["geometry"].simplify(
            tolerance, preserve_topology=True
        )
    result["geometry"] = result["geometry"].apply(make_valid)
    return result


def _smooth_geometry(
    geom: Polygon | MultiPolygon, iterations: int
) -> Polygon | MultiPolygon:
    """Apply Chaikin smoothing to a polygon or multipolygon."""
    if isinstance(geom, MultiPolygon):
        return MultiPolygon([_smooth_polygon(p, iterations) for p in geom.geoms])
    return _smooth_polygon(geom, iterations)


def _smooth_polygon(polygon: Polygon, iterations: int) -> Polygon:
    """Smooth a single polygon's exterior and interior rings."""
    exterior = _chaikin_smooth(np.array(polygon.exterior.coords), iterations)
    interiors = [
        _chaikin_smooth(np.array(ring.coords), iterations) for ring in polygon.interiors
    ]
    try:
        return Polygon(exterior, interiors)
    except Exception:
        return polygon


def _chaikin_smooth(coords: np.ndarray, iterations: int) -> np.ndarray:
    """Apply Chaikin corner-cutting algorithm to a coordinate array.

    Each iteration replaces each edge with two points at 1/4 and 3/4
    along the edge, producing progressively smoother curves.
    The ring is treated as closed (last point connects to first).
    """
    # Remove closing duplicate if present
    if np.array_equal(coords[0], coords[-1]):
        coords = coords[:-1]

    for _ in range(iterations):
        n = len(coords)
        if n < 3:
            break
        new_coords = np.empty((n * 2, 2))
        for i in range(n):
            j = (i + 1) % n
            new_coords[2 * i] = 0.75 * coords[i] + 0.25 * coords[j]
            new_coords[2 * i + 1] = 0.25 * coords[i] + 0.75 * coords[j]
        coords = new_coords

    # Close the ring
    return np.vstack([coords, coords[0]])
