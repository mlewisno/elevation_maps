"""Contour polygon generation from elevation rasters."""

from topo2laser.contours.generator import generate_contours
from topo2laser.contours.layer_calculator import (
    LayerConfig,
    calculate_layers,
    resolve_thickness,
)

__all__ = ["generate_contours", "LayerConfig", "calculate_layers", "resolve_thickness"]
