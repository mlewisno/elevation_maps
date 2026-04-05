"""Render contour layers as 2D and 3D preview images."""

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


def _layer_position(
    layer_idx: int, layer_type: str, water_layers: list[int], land_layers: list[int]
) -> float:
    """Compute color interpolation position (0-1) for a layer within its type group."""
    if layer_type == "water" and len(water_layers) > 1:
        return water_layers.index(layer_idx) / (len(water_layers) - 1)
    elif layer_type != "water" and len(land_layers) > 1:
        return land_layers.index(layer_idx) / (len(land_layers) - 1)
    return 0.5


def render_2d(
    gdf: gpd.GeoDataFrame,
    width_mm: float,
    height_mm: float,
    output_path: Path,
    dpi: int = 150,
) -> Path:
    """Render contour layers as a top-down 2D filled image with legend.

    Draws layers bottom-to-top so higher layers overlap lower ones,
    producing a filled contour map readable by multimodal AI models.

    Args:
        gdf: GeoDataFrame with layer, elevation_min, elevation_max, type, geometry.
        width_mm: Total width in mm.
        height_mm: Total height in mm.
        output_path: Where to save the PNG.
        dpi: Output image resolution.

    Returns:
        Path to the saved PNG.
    """
    import matplotlib.patches as mpatches
    import matplotlib.pyplot as plt
    from matplotlib.collections import PatchCollection
    from matplotlib.patches import PathPatch
    from matplotlib.path import Path as MplPath

    aspect = height_mm / width_mm
    fig_width = 10
    fig, (ax, ax_legend) = plt.subplots(
        1,
        2,
        figsize=(fig_width + 2.5, fig_width * aspect),
        gridspec_kw={"width_ratios": [fig_width, 2.5]},
    )

    water_layers = gdf[gdf["type"] == "water"]["layer"].tolist()
    land_layers = gdf[gdf["type"] != "water"]["layer"].tolist()
    legend_entries = []

    # Draw layers bottom-to-top (sorted by layer index)
    for _, row in gdf.sort_values("layer").iterrows():
        layer_idx = row["layer"]
        layer_type = row["type"]
        position = _layer_position(layer_idx, layer_type, water_layers, land_layers)
        color = _layer_color(layer_type, position)

        polygons = _collect_polygons(row.geometry)
        patches = []
        for poly in polygons:
            if poly.is_empty or poly.area < 1.0:
                continue
            # Build path with exterior + holes
            codes = []
            verts = []
            for ring in [poly.exterior, *poly.interiors]:
                coords = np.array(ring.coords)
                ring_codes = (
                    [MplPath.MOVETO]
                    + [MplPath.LINETO] * (len(coords) - 2)
                    + [MplPath.CLOSEPOLY]
                )
                codes.extend(ring_codes)
                verts.extend(coords.tolist())
            patches.append(PathPatch(MplPath(verts, codes)))

        if patches:
            pc = PatchCollection(
                patches,
                facecolor=color,
                edgecolor=color,
                linewidth=0.5,
            )
            ax.add_collection(pc)

        legend_entries.append(
            (
                color,
                f"L{layer_idx}: {row['elevation_min']:.0f}m"
                f"–{row['elevation_max']:.0f}m"
                f" ({layer_type})",
            )
        )

    ax.set_xlim(0, width_mm)
    ax.set_ylim(0, height_mm)
    ax.set_aspect("equal")
    ax.margins(0)
    # Base layer background so sub-pixel polygon rendering gaps blend
    base_row = gdf.sort_values("layer").iloc[0]
    base_type = base_row["type"]
    base_pos = _layer_position(base_row["layer"], base_type, water_layers, land_layers)
    ax.set_facecolor(_layer_color(base_type, base_pos))
    ax.set_xlabel("mm")
    ax.set_ylabel("mm")
    ax.set_title("Topo Map — 2D Layer Preview")

    # Build legend on the side axis
    ax_legend.set_axis_off()
    ax_legend.set_title("Layers", fontsize=10, fontweight="bold")
    for i, (color, label) in enumerate(reversed(legend_entries)):
        y = i * 0.06
        ax_legend.add_patch(
            mpatches.Rectangle(
                (0.05, y),
                0.15,
                0.04,
                facecolor=color,
                edgecolor="black",
                linewidth=0.5,
                transform=ax_legend.transAxes,
            )
        )
        ax_legend.text(
            0.25,
            y + 0.02,
            label,
            fontsize=7,
            va="center",
            transform=ax_legend.transAxes,
        )
    ax_legend.set_xlim(0, 1)
    ax_legend.set_ylim(0, max(len(legend_entries) * 0.06 + 0.02, 0.1))

    plt.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=dpi, bbox_inches="tight")
    logger.info("2D render saved to %s", output_path)
    plt.close(fig)

    return output_path


def render_per_layer(
    gdf: gpd.GeoDataFrame,
    width_mm: float,
    height_mm: float,
    output_dir: Path,
    alignment_outlines: dict[int, list] | None = None,
    dpi: int = 100,
) -> list[Path]:
    """Render each layer as an individual filled PNG.

    Each image shows a single layer's shape filled with its color
    on a white background, labeled with layer info. If alignment_outlines
    is provided, a dashed blue line shows where the layer above sits.
    """
    import matplotlib.pyplot as plt
    from matplotlib.collections import PatchCollection
    from matplotlib.patches import PathPatch
    from matplotlib.path import Path as MplPath

    water_layers = gdf[gdf["type"] == "water"]["layer"].tolist()
    land_layers = gdf[gdf["type"] != "water"]["layer"].tolist()

    output_dir.mkdir(parents=True, exist_ok=True)
    paths = []

    for _, row in gdf.sort_values("layer").iterrows():
        layer_idx = row["layer"]
        layer_type = row["type"]
        position = _layer_position(layer_idx, layer_type, water_layers, land_layers)
        color = _layer_color(layer_type, position)

        aspect = height_mm / width_mm
        fig, ax = plt.subplots(figsize=(6, 6 * aspect))

        polygons = _collect_polygons(row.geometry)
        patches = []
        for poly in polygons:
            if poly.is_empty or poly.area < 1.0:
                continue
            codes = []
            verts = []
            for ring in [poly.exterior, *poly.interiors]:
                coords = np.array(ring.coords)
                ring_codes = (
                    [MplPath.MOVETO]
                    + [MplPath.LINETO] * (len(coords) - 2)
                    + [MplPath.CLOSEPOLY]
                )
                codes.extend(ring_codes)
                verts.extend(coords.tolist())
            patches.append(PathPatch(MplPath(verts, codes)))

        if patches:
            pc = PatchCollection(
                patches, facecolor=color, edgecolor=color, linewidth=0.5
            )
            ax.add_collection(pc)

        # Draw alignment outline (dashed blue line showing layer above)
        if alignment_outlines and layer_idx in alignment_outlines:
            for line in alignment_outlines[layer_idx]:
                coords = np.array(line.coords)
                ax.plot(
                    coords[:, 0],
                    coords[:, 1],
                    color="#0000FF",
                    linewidth=0.8,
                    linestyle="--",
                    alpha=0.7,
                )

        area_pct = row.geometry.area / (width_mm * height_mm) * 100
        ax.set_xlim(0, width_mm)
        ax.set_ylim(0, height_mm)
        ax.set_aspect("equal")
        ax.margins(0)
        ax.set_title(
            f"L{layer_idx} ({layer_type}): "
            f"{row['elevation_min']:.0f}m–{row['elevation_max']:.0f}m "
            f"({area_pct:.1f}%)",
            fontsize=10,
        )

        out_path = output_dir / f"layer-{layer_idx:02d}-{layer_type}.png"
        fig.savefig(out_path, dpi=dpi, bbox_inches="tight")
        plt.close(fig)
        paths.append(out_path)

    logger.info("Per-layer renders saved to %s", output_dir)
    return paths


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

        position = _layer_position(layer_idx, layer_type, water_layers, land_layers)
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

    # Set aspect ratio — ensure Z is visible relative to X/Y
    z_aspect = max(total_z * 3, max(width_mm, height_mm) * 0.15)
    ax.set_box_aspect([width_mm, height_mm, z_aspect])

    plt.tight_layout()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=dpi, bbox_inches="tight")
    logger.info("3D render saved to %s", output_path)

    if interactive:
        plt.show()
    else:
        plt.close(fig)

    return output_path
