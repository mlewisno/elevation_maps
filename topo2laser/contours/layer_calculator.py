"""Calculate layer elevation breakpoints from physical parameters."""

from dataclasses import dataclass, field


@dataclass
class LayerConfig:
    """Physical layer parameters for the map."""

    material_thickness_mm: float
    layer_count: int
    elevation_min: float  # meters (negative for ocean)
    elevation_max: float  # meters
    _breakpoints: list[float] = field(repr=False, default_factory=list)

    @property
    def total_height_mm(self) -> float:
        return self.material_thickness_mm * self.layer_count

    def breakpoints(self) -> list[float]:
        """Return elevation breakpoints between layers, bottom to top.

        Returns layer_count + 1 values defining layer boundaries.
        Layer 0 spans breakpoints[0] to breakpoints[1], etc.
        """
        return self._breakpoints

    def layer_info(self, layer_index: int) -> dict:
        """Return metadata for a given layer."""
        bp = self._breakpoints
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
    max_water_layers: int = 4,
) -> LayerConfig:
    """Calculate layer configuration from physical parameters.

    Provide either total_height_mm or layer_count (not both).

    Water layers are capped at max_water_layers. Remaining layers are
    allocated to land, giving land features higher vertical resolution.
    Set max_water_layers to 0 to disable water layer capping.
    """
    if total_height_mm is not None and layer_count is not None:
        raise ValueError("Provide total_height_mm or layer_count, not both")
    if total_height_mm is None and layer_count is None:
        raise ValueError("Provide either total_height_mm or layer_count")

    if layer_count is None and total_height_mm is not None:
        layer_count = max(1, round(total_height_mm / material_thickness_mm))

    assert layer_count is not None  # guaranteed by validation above

    breakpoints = _compute_breakpoints(
        elevation_min, elevation_max, layer_count, max_water_layers
    )

    return LayerConfig(
        material_thickness_mm=material_thickness_mm,
        layer_count=layer_count,
        elevation_min=elevation_min,
        elevation_max=elevation_max,
        _breakpoints=breakpoints,
    )


def _compute_breakpoints(
    elevation_min: float,
    elevation_max: float,
    layer_count: int,
    max_water_layers: int,
) -> list[float]:
    """Compute non-uniform breakpoints favoring land resolution.

    If the data has both water (< 0) and land (>= 0) and the uniform
    distribution would use more than max_water_layers for water, cap
    water at max_water_layers and give the rest to land.
    """
    if elevation_min >= 0 or max_water_layers <= 0:
        # No water or capping disabled — uniform intervals
        interval = (elevation_max - elevation_min) / layer_count
        return [elevation_min + i * interval for i in range(layer_count + 1)]

    water_range = abs(elevation_min)
    land_range = elevation_max
    total_range = water_range + land_range

    # How many layers would water get with uniform intervals?
    uniform_water = round(layer_count * water_range / total_range)

    if uniform_water <= max_water_layers:
        # Uniform distribution doesn't exceed cap — use it
        interval = total_range / layer_count
        return [elevation_min + i * interval for i in range(layer_count + 1)]

    # Cap water layers and give the rest to land
    water_layers = max_water_layers
    land_layers = layer_count - water_layers

    water_interval = water_range / water_layers
    land_interval = land_range / land_layers

    breakpoints = []
    # Water breakpoints (bottom to sea level)
    for i in range(water_layers):
        breakpoints.append(elevation_min + i * water_interval)
    # Sea level boundary
    breakpoints.append(0.0)
    # Land breakpoints (sea level to peak)
    for i in range(1, land_layers + 1):
        breakpoints.append(i * land_interval)

    return breakpoints
