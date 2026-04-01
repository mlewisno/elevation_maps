"""Main elevation data fetching orchestration."""

import logging
from dataclasses import dataclass
from pathlib import Path

from topo2laser.elevation.merge import merge_land_and_ocean
from topo2laser.elevation.sources import fetch_3dep, fetch_etopo

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

    Strategy:
    1. Fetch ETOPO 2022 (combined land + ocean, ~450m resolution)
    2. Try fetching 3DEP (US only, 10m resolution) for land
    3. If 3DEP available, merge: 3DEP for land, ETOPO for ocean
    4. Otherwise, use ETOPO alone
    """
    bbox_slug = (
        f"{bbox.south:.2f}_{bbox.west:.2f}_{bbox.north:.2f}_{bbox.east:.2f}"
    ).replace("-", "m")
    run_cache = cache_dir / bbox_slug

    # Check for cached merged result first
    merged_path = run_cache / "merged.tif"
    if merged_path.exists():
        logger.info("Using cached merged elevation: %s", merged_path)
        return merged_path

    logger.info(
        "Fetching elevation for bbox: %.4f,%.4f,%.4f,%.4f",
        bbox.south,
        bbox.west,
        bbox.north,
        bbox.east,
    )

    # Always fetch ETOPO for ocean bathymetry
    etopo_path = fetch_etopo(
        bbox.south, bbox.west, bbox.north, bbox.east, cache_dir=run_cache
    )

    if not include_bathymetry:
        return etopo_path

    # Try 3DEP for higher-resolution land data
    dep3_path = fetch_3dep(
        bbox.south, bbox.west, bbox.north, bbox.east, cache_dir=run_cache
    )

    if dep3_path is None:
        logger.info("No 3DEP data — using ETOPO only")
        return etopo_path

    # Merge: 3DEP for land, ETOPO for ocean
    logger.info("Merging 3DEP land + ETOPO ocean...")
    return merge_land_and_ocean(etopo_path, dep3_path, merged_path)
