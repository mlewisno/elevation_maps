"""Calculate layer elevation breakpoints from physical parameters."""

from dataclasses import dataclass


@dataclass
class LayerConfig:
    """Physical layer parameters for the map."""

    material_thickness_mm: float
    layer_count: int
    elevation_min: float  # meters (negative for ocean)
    elevation_max: float  # meters
    elevation_interval: float  # meters per layer

    @property
    def total_height_mm(self) -> float:
        return self.material_thickness_mm * self.layer_count

    def breakpoints(self) -> list[float]:
        """Return elevation breakpoints between layers, bottom to top.

        Returns layer_count + 1 values defining layer boundaries.
        Layer 0 spans breakpoints[0] to breakpoints[1], etc.
        """
        return [
            self.elevation_min + i * self.elevation_interval
            for i in range(self.layer_count + 1)
        ]

    def layer_info(self, layer_index: int) -> dict:
        """Return metadata for a given layer."""
        bp = self.breakpoints()
        low = bp[layer_index]
        high = bp[layer_index + 1]
        is_water = high <= 0
        is_land = low >= 0
        if not is_water and not is_land:
            layer_type = "mixed"
        elif is_water:
            layer_type = "water"
        else:
            layer_type = "land"

        return {
            "index": layer_index,
            "elevation_min": low,
            "elevation_max": high,
            "type": layer_type,
        }


MATERIAL_PRESETS = {
    "cardstock": 1.5,
    "thin-ply": 3.0,
    "thick-ply": 6.0,
    "acrylic-thin": 3.0,
    "acrylic-thick": 6.0,
}


def resolve_thickness(value: str) -> float:
    """Resolve a thickness value — either a preset name or mm value."""
    if value in MATERIAL_PRESETS:
        return MATERIAL_PRESETS[value]
    cleaned = value.rstrip("mm").strip()
    return float(cleaned)


def calculate_layers(
    elevation_min: float,
    elevation_max: float,
    material_thickness_mm: float,
    total_height_mm: float | None = None,
    layer_count: int | None = None,
) -> LayerConfig:
    """Calculate layer configuration from physical parameters.

    Provide either total_height_mm or layer_count (not both).
    """
    if total_height_mm is not None and layer_count is not None:
        raise ValueError("Provide total_height_mm or layer_count, not both")
    if total_height_mm is None and layer_count is None:
        raise ValueError("Provide either total_height_mm or layer_count")

    elevation_range = elevation_max - elevation_min

    if layer_count is not None:
        elevation_interval = elevation_range / layer_count
    else:
        layer_count = max(1, round(total_height_mm / material_thickness_mm))
        elevation_interval = elevation_range / layer_count

    return LayerConfig(
        material_thickness_mm=material_thickness_mm,
        layer_count=layer_count,
        elevation_min=elevation_min,
        elevation_max=elevation_max,
        elevation_interval=elevation_interval,
    )
