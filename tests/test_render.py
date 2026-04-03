"""Tests for the 2D and 3D render module."""

import geopandas as gpd
from shapely.geometry import MultiPolygon, Polygon, box

from topo2laser.render.renderer import (
    _collect_polygons,
    _layer_color,
    _layer_position,
    render_2d,
    render_3d,
)


def _make_gdf():
    """Create a simple test GeoDataFrame with 3 layers."""
    records = [
        {
            "layer": 0,
            "elevation_min": -100.0,
            "elevation_max": 0.0,
            "type": "water",
            "geometry": box(10, 10, 190, 140),
        },
        {
            "layer": 1,
            "elevation_min": 0.0,
            "elevation_max": 500.0,
            "type": "land",
            "geometry": box(30, 30, 170, 120),
        },
        {
            "layer": 2,
            "elevation_min": 500.0,
            "elevation_max": 1000.0,
            "type": "land",
            "geometry": box(60, 50, 140, 100),
        },
    ]
    return gpd.GeoDataFrame(records)


class TestCollectPolygons:
    def test_single_polygon(self):
        poly = box(0, 0, 10, 10)
        result = _collect_polygons(poly)
        assert len(result) == 1
        assert isinstance(result[0], Polygon)

    def test_multipolygon(self):
        mp = MultiPolygon([box(0, 0, 5, 5), box(10, 10, 15, 15)])
        result = _collect_polygons(mp)
        assert len(result) == 2

    def test_empty_geometry(self):
        from shapely.geometry import Point

        result = _collect_polygons(Point(0, 0))
        assert result == []


class TestLayerColor:
    def test_water_returns_blue_tones(self):
        r, g, b, a = _layer_color("water", 0.5)
        assert b > r

    def test_land_returns_green_tones(self):
        r, g, b, a = _layer_color("land", 0.5)
        assert g > b

    def test_position_varies_color(self):
        low = _layer_color("land", 0.0)
        high = _layer_color("land", 1.0)
        assert low != high


class TestLayerPosition:
    def test_water_position(self):
        assert _layer_position(0, "water", [0, 1], [2, 3]) == 0.0
        assert _layer_position(1, "water", [0, 1], [2, 3]) == 1.0

    def test_land_position(self):
        assert _layer_position(2, "land", [0], [2, 3, 4]) == 0.0
        assert _layer_position(4, "land", [0], [2, 3, 4]) == 1.0

    def test_single_layer_returns_half(self):
        assert _layer_position(0, "water", [0], []) == 0.5


class TestRender2D:
    def test_saves_png(self, tmp_path):
        gdf = _make_gdf()
        output = tmp_path / "render_2d.png"
        result = render_2d(
            gdf=gdf,
            width_mm=200.0,
            height_mm=150.0,
            output_path=output,
        )
        assert result == output
        assert output.exists()
        assert output.stat().st_size > 0

    def test_creates_parent_dirs(self, tmp_path):
        gdf = _make_gdf()
        output = tmp_path / "nested" / "dir" / "render_2d.png"
        render_2d(
            gdf=gdf,
            width_mm=200.0,
            height_mm=150.0,
            output_path=output,
        )
        assert output.exists()

    def test_output_has_reasonable_size(self, tmp_path):
        """2D render should be larger than a trivial empty image."""
        gdf = _make_gdf()
        output = tmp_path / "render_2d.png"
        render_2d(gdf=gdf, width_mm=200.0, height_mm=150.0, output_path=output)
        assert output.stat().st_size > 5000


class TestRender3D:
    def test_saves_png(self, tmp_path):
        gdf = _make_gdf()
        output = tmp_path / "render.png"
        result = render_3d(
            gdf=gdf,
            material_thickness_mm=3.0,
            width_mm=200.0,
            height_mm=150.0,
            output_path=output,
        )
        assert result == output
        assert output.exists()
        assert output.stat().st_size > 0

    def test_creates_parent_dirs(self, tmp_path):
        gdf = _make_gdf()
        output = tmp_path / "nested" / "dir" / "render.png"
        render_3d(
            gdf=gdf,
            material_thickness_mm=3.0,
            width_mm=200.0,
            height_mm=150.0,
            output_path=output,
        )
        assert output.exists()
