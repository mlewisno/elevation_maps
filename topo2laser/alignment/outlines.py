"""Generate alignment outlines between layers."""

import geopandas as gpd
from shapely.geometry import MultiPolygon, Polygon


def generate_alignment_outlines(
    gdf: gpd.GeoDataFrame,
) -> dict[int, list]:
    """For each layer, get the boundary outline of the layer above it.

    This outline is engraved onto the current layer as a visual
    alignment guide for glue-up.

    Returns:
        Dict mapping layer index → list of LineString/MultiLineString
        geometries to engrave. The topmost layer has no entry.
    """
    outlines = {}
    sorted_layers = sorted(gdf["layer"].unique())

    for i, layer_idx in enumerate(sorted_layers[:-1]):
        next_layer_idx = sorted_layers[i + 1]
        next_geom = gdf[gdf["layer"] == next_layer_idx].geometry.values[0]
        outlines[layer_idx] = _extract_boundaries(next_geom)

    return outlines


def _extract_boundaries(geom: Polygon | MultiPolygon) -> list:
    """Extract boundary linestrings from a polygon or multipolygon."""
    if isinstance(geom, MultiPolygon):
        boundaries = []
        for poly in geom.geoms:
            boundaries.append(poly.exterior)
            boundaries.extend(poly.interiors)
        return boundaries
    else:
        result = [geom.exterior]
        result.extend(geom.interiors)
        return result
