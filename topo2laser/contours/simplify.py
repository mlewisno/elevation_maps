"""Polygon simplification and smoothing for laser-cuttable output."""

import geopandas as gpd
import numpy as np
from shapely.geometry import MultiPolygon, Polygon
from shapely.validation import make_valid

DEFAULT_MIN_POLYGON_MM = 5.0


def simplify_contours(
    gdf: gpd.GeoDataFrame,
    tolerance: float = 0.5,
    smooth_iterations: int = 3,
    min_polygon_mm: float = DEFAULT_MIN_POLYGON_MM,
) -> gpd.GeoDataFrame:
    """Simplify and smooth contour polygons for cleaner laser cuts.

    First applies Chaikin corner-cutting to smooth staircase edges from
    raster vectorization, then Douglas-Peucker to reduce vertex count,
    then filters out polygons too small to laser cut.

    Args:
        gdf: GeoDataFrame with contour polygons (in mm coordinates).
        tolerance: Douglas-Peucker tolerance in mm after smoothing.
        smooth_iterations: Number of Chaikin smoothing passes.
        min_polygon_mm: Minimum bounding box dimension in mm. Polygons
            smaller than this in both width and height are dropped.
            Set to 0 to keep all polygons.

    Returns:
        GeoDataFrame with smoothed and filtered geometries.
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
    if min_polygon_mm > 0:
        result["geometry"] = result["geometry"].apply(
            lambda geom: _filter_small_polygons(geom, min_polygon_mm)
        )
        result = result[~result["geometry"].is_empty].reset_index(drop=True)
    return result


def _filter_small_polygons(
    geom: Polygon | MultiPolygon, min_dim_mm: float
) -> Polygon | MultiPolygon:
    """Remove polygons whose bounding box is smaller than min_dim_mm."""
    if isinstance(geom, MultiPolygon):
        kept = [p for p in geom.geoms if _polygon_large_enough(p, min_dim_mm)]
        if not kept:
            return Polygon()
        if len(kept) == 1:
            return kept[0]
        return MultiPolygon(kept)
    if _polygon_large_enough(geom, min_dim_mm):
        return geom
    return Polygon()


def _polygon_large_enough(polygon: Polygon, min_dim_mm: float) -> bool:
    """Check if polygon bbox exceeds min_dim_mm in at least one dimension."""
    minx, miny, maxx, maxy = polygon.bounds
    width = maxx - minx
    height = maxy - miny
    return width >= min_dim_mm or height >= min_dim_mm


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
