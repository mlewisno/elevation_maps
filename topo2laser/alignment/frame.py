"""Generate optional rectangular frame piece."""

from shapely.geometry import Polygon, box


def generate_frame(
    width_mm: float,
    height_mm: float,
    border_mm: float = 15.0,
    inner_cutout: Polygon | None = None,
) -> Polygon:
    """Generate a rectangular frame piece.

    Args:
        width_mm: Map content width in mm.
        height_mm: Map content height in mm.
        border_mm: Frame border width in mm.
        inner_cutout: Optional polygon for the inner cutout. If None,
            the inner cutout is the full content rectangle.

    Returns:
        Frame polygon (outer rectangle minus inner cutout).
    """
    outer = box(
        -border_mm,
        -border_mm,
        width_mm + border_mm,
        height_mm + border_mm,
    )

    if inner_cutout is None:
        inner = box(0, 0, width_mm, height_mm)
    else:
        inner = inner_cutout

    return outer.difference(inner)
