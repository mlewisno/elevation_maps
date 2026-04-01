"""Convert shapely geometries to SVG path data strings."""

from shapely.geometry import (
    LinearRing,
    LineString,
    MultiLineString,
    MultiPolygon,
    Polygon,
)


def polygon_to_svg_d(polygon: Polygon, flip_y: float = 0) -> str:
    """Convert a shapely Polygon to an SVG path d-string.

    Includes exterior ring and any interior rings (holes).
    If flip_y > 0, flips Y coordinates (SVG y-axis points down).
    """
    parts = [_ring_to_d(polygon.exterior, flip_y)]
    for interior in polygon.interiors:
        parts.append(_ring_to_d(interior, flip_y))
    return " ".join(parts)


def multipolygon_to_svg_ds(
    geom: Polygon | MultiPolygon, flip_y: float = 0
) -> list[str]:
    """Convert a Polygon or MultiPolygon to a list of SVG path d-strings."""
    if isinstance(geom, MultiPolygon):
        return [polygon_to_svg_d(p, flip_y) for p in geom.geoms]
    return [polygon_to_svg_d(geom, flip_y)]


def linestring_to_svg_d(line: LineString | LinearRing, flip_y: float = 0) -> str:
    """Convert a LineString or LinearRing to an SVG path d-string."""
    return _ring_to_d(line, flip_y)


def lines_to_svg_ds(lines: list, flip_y: float = 0) -> list[str]:
    """Convert a list of line geometries to SVG path d-strings."""
    result = []
    for line in lines:
        if isinstance(line, MultiLineString):
            for part in line.geoms:
                result.append(linestring_to_svg_d(part, flip_y))
        else:
            result.append(linestring_to_svg_d(line, flip_y))
    return result


def _ring_to_d(ring, flip_y: float = 0) -> str:
    """Convert a coordinate sequence to SVG path M/L/Z commands."""
    coords = list(ring.coords)
    if not coords:
        return ""

    def fmt(x, y):
        if flip_y > 0:
            y = flip_y - y
        return f"{x:.3f},{y:.3f}"

    parts = [f"M {fmt(*coords[0])}"]
    for x, y in coords[1:]:
        parts.append(f"L {fmt(x, y)}")
    parts.append("Z")
    return " ".join(parts)
