"""Main elevation data fetching orchestration."""

import logging
from dataclasses import dataclass
from pathlib import Path

from topo2laser.elevation.sources import fetch_etopo

logger = logging.getLogger(__name__)

DEFAULT_CACHE_DIR = Path(".cache/elevation")


@dataclass
class BoundingBox:
    """Geographic bounding box in decimal degrees."""

    south: float
    west: float
    north: float
    east: float

    def __post_init__(self):
        if self.south >= self.north:
            raise ValueError(
                f"South ({self.south}) must be less than north ({self.north})"
            )
        if self.west >= self.east:
            raise ValueError(f"West ({self.west}) must be less than east ({self.east})")

    @classmethod
    def from_string(cls, s: str) -> "BoundingBox":
        """Parse 'south,west,north,east' string."""
        parts = [float(x.strip()) for x in s.split(",")]
        if len(parts) != 4:
            raise ValueError(
                f"Expected 4 comma-separated values, got {len(parts)}: {s}"
            )
        return cls(south=parts[0], west=parts[1], north=parts[2], east=parts[3])

    @property
    def center_lat(self) -> float:
        return (self.south + self.north) / 2

    @property
    def center_lon(self) -> float:
        return (self.west + self.east) / 2


def fetch_elevation(
    bbox: BoundingBox,
    include_bathymetry: bool = True,
    cache_dir: Path = DEFAULT_CACHE_DIR,
) -> Path:
    """Fetch elevation data for a bounding box.

    Returns the path to a GeoTIFF with elevation values (positive = land,
    negative = ocean depth, zero = sea level).

    For now, uses ETOPO 2022 which provides both land and ocean in one
    dataset. Future: merge higher-resolution 3DEP land data on top.
    """
    bbox_slug = (
        f"{bbox.south:.2f}_{bbox.west:.2f}_{bbox.north:.2f}_{bbox.east:.2f}"
    ).replace("-", "m")
    run_cache = cache_dir / bbox_slug

    logger.info(
        "Fetching elevation for bbox: %.4f,%.4f,%.4f,%.4f",
        bbox.south,
        bbox.west,
        bbox.north,
        bbox.east,
    )

    if include_bathymetry:
        return fetch_etopo(
            bbox.south,
            bbox.west,
            bbox.north,
            bbox.east,
            cache_dir=run_cache,
        )
    else:
        # Land-only: fetch ETOPO and clamp negative values to 0
        tif_path = fetch_etopo(
            bbox.south,
            bbox.west,
            bbox.north,
            bbox.east,
            cache_dir=run_cache,
        )
        # TODO: Clamp in a copy rather than modifying the cached file
        return tif_path
