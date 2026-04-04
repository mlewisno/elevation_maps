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
    water_layers: int | None = None,
    land_layers: int | None = None,
) -> LayerConfig:
    """Calculate layer configuration from physical parameters.

    Layer count can be determined several ways (in priority order):
    1. Both water_layers and land_layers set → total = water + land
    2. One of water_layers/land_layers set + layer_count → other = remainder
    3. layer_count or total_height_mm → use max_water_layers cap
    """
    # Resolve explicit water/land layer counts
    if water_layers is not None and land_layers is not None:
        layer_count = water_layers + land_layers
    elif water_layers is not None and layer_count is not None:
        land_layers = layer_count - water_layers
    elif land_layers is not None and layer_count is not None:
        water_layers = layer_count - land_layers

    if total_height_mm is not None and layer_count is not None:
        raise ValueError("Provide total_height_mm or layer_count, not both")
    if total_height_mm is None and layer_count is None:
        raise ValueError("Provide either total_height_mm or layer_count")

    if layer_count is None and total_height_mm is not None:
        layer_count = max(1, round(total_height_mm / material_thickness_mm))

    assert layer_count is not None  # guaranteed by validation above

    # Use explicit counts if both are resolved, otherwise cap-based
    if water_layers is not None and land_layers is not None:
        breakpoints = _compute_breakpoints_explicit(
            elevation_min, elevation_max, water_layers, land_layers
        )
    else:
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


def _compute_breakpoints_explicit(
    elevation_min: float,
    elevation_max: float,
    water_layers: int,
    land_layers: int,
) -> list[float]:
    """Compute breakpoints with explicit water/land layer counts."""
    breakpoints = []

    if water_layers > 0 and elevation_min < 0:
        water_range = abs(elevation_min)
        water_interval = water_range / water_layers
        for i in range(water_layers):
            breakpoints.append(elevation_min + i * water_interval)
        breakpoints.append(0.0)
    elif water_layers > 0:
        # Water layers requested but no water in data — use uniform
        interval = (elevation_max - elevation_min) / (water_layers + land_layers)
        for i in range(water_layers):
            breakpoints.append(elevation_min + i * interval)
        breakpoints.append(elevation_min + water_layers * interval)
    else:
        breakpoints.append(elevation_min)

    if land_layers > 0:
        land_min = breakpoints[-1]
        land_range = elevation_max - land_min
        land_interval = land_range / land_layers
        for i in range(1, land_layers + 1):
            breakpoints.append(land_min + i * land_interval)

    return breakpoints


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
