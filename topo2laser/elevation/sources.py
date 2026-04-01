"""Data source adapters for elevation and bathymetry data."""

import logging
from pathlib import Path

import numpy as np
import rasterio
from rasterio.crs import CRS
from rasterio.transform import from_bounds

try:
    import py3dep

    HAS_PY3DEP = True
except ImportError:
    HAS_PY3DEP = False

logger = logging.getLogger(__name__)

ETOPO_CATALOG_URL = (
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/"
    "15s/15s_surface_elev_netcdf/"
)
ETOPO_TILE_PATTERN = "ETOPO_2022_v1_15s_{lat}{lon}_surface.nc"


def _tile_label(lat: int, lon: int) -> str:
    """Convert integer lat/lon to ETOPO tile label like N30W165."""
    lat_prefix = "N" if lat >= 0 else "S"
    lon_prefix = "E" if lon >= 0 else "W"
    return f"{lat_prefix}{abs(lat):02d}{lon_prefix}{abs(lon):03d}"


def _tiles_for_bbox(
    south: float,
    west: float,
    north: float,
    east: float,
) -> list[str]:
    """Determine which ETOPO 15° tiles cover a bounding box.

    Tile names encode: latitude = north edge of tile, longitude = west edge.
    Example: N30W165 covers lat 15-30, lon -165 to -150.
    Each tile spans 15° in each direction.
    """
    import math

    # Find which tile contains each corner
    # Tile north edge: ceiling of lat to next 15° boundary
    # Tile west edge: floor of lon to previous 15° boundary
    lat_min_tile = math.ceil(south / 15) * 15
    if lat_min_tile == south:
        lat_min_tile = int(south)
    else:
        lat_min_tile = int(lat_min_tile)
    lat_max_tile = math.ceil(north / 15) * 15

    lon_min_tile = math.floor(west / 15) * 15
    lon_max_tile = math.floor(east / 15) * 15

    tiles = []
    for tile_north in range(lat_min_tile, int(lat_max_tile) + 1, 15):
        for tile_west in range(int(lon_min_tile), int(lon_max_tile) + 1, 15):
            if tile_north > 90 or tile_north < -75:
                continue
            label = _tile_label(tile_north, tile_west)
            tiles.append(label)
    return tiles


def fetch_etopo(
    south: float,
    west: float,
    north: float,
    east: float,
    cache_dir: Path,
) -> Path:
    """Fetch ETOPO 2022 data for a bounding box via OPeNDAP.

    Downloads the relevant tiles, subsets to the bounding box, and saves
    as a GeoTIFF. Returns the path to the output file.

    Uses xarray + OPeNDAP for streaming access (no full tile download).
    """
    import xarray as xr

    cache_dir.mkdir(parents=True, exist_ok=True)
    output_path = cache_dir / "etopo_merged.tif"

    if output_path.exists():
        logger.info("Using cached ETOPO data: %s", output_path)
        return output_path

    tiles = _tiles_for_bbox(south, west, north, east)
    logger.info("ETOPO tiles needed: %s", tiles)

    datasets = []
    for tile_label in tiles:
        filename = ETOPO_TILE_PATTERN.format(lat=tile_label[:3], lon=tile_label[3:])
        url = f"{ETOPO_CATALOG_URL}{filename}"
        logger.info("Opening ETOPO tile: %s", url)
        try:
            ds = xr.open_dataset(url)
            subset = ds["z"].sel(
                lat=slice(south, north),
                lon=slice(west, east),
            )
            if subset.size > 0:
                datasets.append(subset)
            else:
                logger.debug("Tile %s has no data in bbox, skipping", tile_label)
        except Exception:
            logger.warning("Failed to open tile %s, skipping", tile_label)

    if not datasets:
        raise RuntimeError(
            f"No ETOPO data found for bbox ({south}, {west}, {north}, {east})"
        )

    if len(datasets) == 1:
        merged = datasets[0]
    else:
        merged = xr.combine_by_coords(datasets)["z"]

    elevation = merged.values
    lats = merged.lat.values
    lons = merged.lon.values

    _write_geotiff(
        elevation,
        lats,
        lons,
        output_path,
        description="ETOPO 2022 15 arc-second elevation + bathymetry",
    )

    logger.info(
        "ETOPO data saved to %s (%d x %d pixels)", output_path, *elevation.shape
    )
    return output_path


def _write_geotiff(
    data: np.ndarray,
    lats: np.ndarray,
    lons: np.ndarray,
    output_path: Path,
    description: str = "",
) -> None:
    """Write a 2D elevation array to GeoTIFF with EPSG:4326 CRS."""
    # rasterio expects north-up orientation (lat descending)
    if lats[0] < lats[-1]:
        data = np.flipud(data)
        lats = lats[::-1]

    height, width = data.shape
    transform = from_bounds(
        west=float(lons.min()),
        south=float(lats.min()),
        east=float(lons.max()),
        north=float(lats.max()),
        width=width,
        height=height,
    )

    with rasterio.open(
        output_path,
        "w",
        driver="GTiff",
        height=height,
        width=width,
        count=1,
        dtype=data.dtype,
        crs=CRS.from_epsg(4326),
        transform=transform,
    ) as dst:
        dst.write(data, 1)
        dst.update_tags(description=description)


def fetch_3dep(
    south: float,
    west: float,
    north: float,
    east: float,
    cache_dir: Path,
    resolution: int = 10,
) -> Path | None:
    """Fetch USGS 3DEP elevation data for a bounding box.

    Uses py3dep to fetch DEM at the specified resolution (meters).
    Returns path to GeoTIFF, or None if py3dep is not installed or
    the area is outside 3DEP coverage.

    Args:
        resolution: DEM resolution in meters. 10 (default) or 30.
    """
    if not HAS_PY3DEP:
        logger.info("py3dep not installed — skipping 3DEP fetch")
        return None

    cache_dir.mkdir(parents=True, exist_ok=True)
    output_path = cache_dir / f"3dep_{resolution}m.tif"

    if output_path.exists():
        logger.info("Using cached 3DEP data: %s", output_path)
        return output_path

    logger.info("Fetching 3DEP %dm data...", resolution)
    try:
        dem = py3dep.get_dem((west, south, east, north), resolution=resolution)
        dem.rio.to_raster(str(output_path))
        logger.info(
            "3DEP data saved to %s (%d x %d pixels)",
            output_path,
            dem.shape[1],
            dem.shape[0],
        )
        return output_path
    except Exception as e:
        logger.warning("3DEP fetch failed (area may be outside US): %s", e)
        return None
