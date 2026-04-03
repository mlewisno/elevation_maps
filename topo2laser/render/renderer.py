"""Render stacked contour layers as a 3D preview image."""

import logging
from pathlib import Path

import geopandas as gpd
import numpy as np
from shapely.geometry import MultiPolygon, Polygon

logger = logging.getLogger(__name__)

# Colors for water and land layers (RGBA)
WATER_CMAP = "Blues_r"
LAND_CMAP = "YlGn"


def _polygon_to_verts(polygon: Polygon) -> list[np.ndarray]:
    """Extract exterior and hole coordinates from a Shapely polygon."""
    verts = [np.array(polygon.exterior.coords)]
    for interior in polygon.interiors:
        verts.append(np.array(interior.coords))
    return verts


def _collect_polygons(geometry) -> list[Polygon]:
    """Flatten a geometry into a list of Polygons."""
    if isinstance(geometry, Polygon):
        return [geometry]
    if isinstance(geometry, MultiPolygon):
        return list(geometry.geoms)
    return []


def _layer_color(layer_type: str, position: float) -> tuple[float, ...]:
    """Return an RGBA color for a layer based on type and relative position.

    position: 0.0 (lowest) to 1.0 (highest) within the type group.
    """
    import matplotlib.pyplot as plt

    if layer_type == "water":
        cmap = plt.get_cmap("Blues")
        return cmap(0.3 + 0.5 * (1.0 - position))
    else:
        cmap = plt.get_cmap("YlGn")
        return cmap(0.25 + 0.55 * position)


def render_3d(
    gdf: gpd.GeoDataFrame,
    material_thickness_mm: float,
    width_mm: float,
    height_mm: float,
    output_path: Path,
    interactive: bool = False,
    dpi: int = 150,
) -> Path:
    """Render the contour layers as a 3D stepped surface.

    Each layer is drawn as filled polygons at its physical Z height
    (layer_index * material_thickness_mm), producing the terraced
    appearance of the real laser-cut result.

    Args:
        gdf: GeoDataFrame with layer, type, and geometry columns (mm coords).
        material_thickness_mm: Physical thickness of each layer.
        width_mm: Total width in mm.
        height_mm: Total height in mm.
        output_path: Where to save the PNG.
        interactive: If True, open an interactive matplotlib window.
        dpi: Output image resolution.

    Returns:
        Path to the saved PNG.
    """
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    fig = plt.figure(figsize=(12, 9))
    ax = fig.add_subplot(111, projection="3d")

    # Count water/land layers for color interpolation
    water_layers = gdf[gdf["type"] == "water"]["layer"].tolist()
    land_layers = gdf[gdf["type"] != "water"]["layer"].tolist()

    for _, row in gdf.iterrows():
        layer_idx = row["layer"]
        layer_type = row["type"]
        z = layer_idx * material_thickness_mm

        # Compute color position within the type group
        if layer_type == "water" and len(water_layers) > 1:
            position = water_layers.index(layer_idx) / (len(water_layers) - 1)
        elif layer_type != "water" and len(land_layers) > 1:
            position = land_layers.index(layer_idx) / (len(land_layers) - 1)
        else:
            position = 0.5

        color = _layer_color(layer_type, position)

        polygons = _collect_polygons(row.geometry)
        for poly in polygons:
            if poly.is_empty or poly.area < 1.0:
                continue
            coords = np.array(poly.exterior.coords)
            # Create 3D vertices at this layer's Z height
            verts_3d = [(x, y, z) for x, y in coords]
            collection = Poly3DCollection(
                [verts_3d],
                facecolor=color,
                edgecolor=(0, 0, 0, 0.15),
                linewidth=0.3,
            )
            ax.add_collection3d(collection)

    # Set axis limits and labels
    total_z = gdf["layer"].max() * material_thickness_mm
    ax.set_xlim(0, width_mm)
    ax.set_ylim(0, height_mm)
    ax.set_zlim(0, max(total_z * 1.1, material_thickness_mm))

    ax.set_xlabel("Width (mm)")
    ax.set_ylabel("Height (mm)")
    ax.set_zlabel("Thickness (mm)")
    ax.set_title("Laser-Cut Topo Map Preview")

    # Set camera angle for a nice isometric-ish view
    ax.view_init(elev=35, azim=-60)

    # Equal aspect ratio for X and Y
    ax.set_box_aspect([width_mm, height_mm, total_z * 3])

    plt.tight_layout()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=dpi, bbox_inches="tight")
    logger.info("3D render saved to %s", output_path)

    if interactive:
        plt.show()
    else:
        plt.close(fig)

    return output_path
