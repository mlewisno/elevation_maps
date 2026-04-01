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
    high_res_land: bool = False,
    cache_dir: Path = DEFAULT_CACHE_DIR,
) -> Path:
    """Fetch elevation data for a bounding box.

    Returns the path to a GeoTIFF with elevation values (positive = land,
    negative = ocean depth, zero = sea level).

    Args:
        include_bathymetry: Include ocean depth data (negative values).
        high_res_land: Merge USGS 3DEP 10m land data over ETOPO.
            Slower first run but much sharper land contours.
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

    # Always fetch ETOPO (combined land + ocean)
    etopo_path = fetch_etopo(
        bbox.south, bbox.west, bbox.north, bbox.east, cache_dir=run_cache
    )

    if not high_res_land:
        return etopo_path

    # High-res mode: merge 3DEP land over ETOPO ocean
    merged_path = run_cache / "merged.tif"
    if merged_path.exists():
        logger.info("Using cached merged elevation: %s", merged_path)
        return merged_path

    dep3_path = fetch_3dep(
        bbox.south, bbox.west, bbox.north, bbox.east, cache_dir=run_cache
    )

    if dep3_path is None:
        logger.info("No 3DEP data available — using ETOPO only")
        return etopo_path

    logger.info("Merging 3DEP land + ETOPO ocean...")
    return merge_land_and_ocean(etopo_path, dep3_path, merged_path)
