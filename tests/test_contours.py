"""Tests for contour generation."""

import pytest

from topo2laser.contours.layer_calculator import (
    calculate_layers,
    resolve_thickness,
)


class TestResolveThickness:
    def test_preset_thin_ply(self):
        assert resolve_thickness("thin-ply") == 3.0

    def test_preset_cardstock(self):
        assert resolve_thickness("cardstock") == 1.5

    def test_mm_value(self):
        assert resolve_thickness("3mm") == 3.0

    def test_bare_number(self):
        assert resolve_thickness("2.5") == 2.5


class TestCalculateLayers:
    def test_from_layer_count(self):
        config = calculate_layers(
            elevation_min=-1000,
            elevation_max=1500,
            material_thickness_mm=3.0,
            layer_count=10,
        )
        assert config.layer_count == 10
        assert config.total_height_mm == 30.0

    def test_from_total_height(self):
        config = calculate_layers(
            elevation_min=-1000,
            elevation_max=1500,
            material_thickness_mm=3.0,
            total_height_mm=36.0,
        )
        assert config.layer_count == 12

    def test_both_raises(self):
        with pytest.raises(ValueError, match="not both"):
            calculate_layers(
                elevation_min=0,
                elevation_max=1000,
                material_thickness_mm=3.0,
                total_height_mm=30.0,
                layer_count=10,
            )

    def test_neither_raises(self):
        with pytest.raises(ValueError, match="either"):
            calculate_layers(
                elevation_min=0,
                elevation_max=1000,
                material_thickness_mm=3.0,
            )

    def test_breakpoints(self):
        config = calculate_layers(
            elevation_min=0,
            elevation_max=1000,
            material_thickness_mm=3.0,
            layer_count=5,
        )
        bp = config.breakpoints()
        assert len(bp) == 6  # 5 layers = 6 breakpoints
        assert bp[0] == 0.0
        assert bp[-1] == 1000.0

    def test_layer_info_water(self):
        config = calculate_layers(
            elevation_min=-500,
            elevation_max=500,
            material_thickness_mm=3.0,
            layer_count=4,
        )
        info = config.layer_info(0)
        assert info["type"] == "water"

    def test_layer_info_land(self):
        config = calculate_layers(
            elevation_min=-500,
            elevation_max=500,
            material_thickness_mm=3.0,
            layer_count=4,
        )
        info = config.layer_info(config.layer_count - 1)
        assert info["type"] == "land"

    def test_layer_info_mixed(self):
        config = calculate_layers(
            elevation_min=-600,
            elevation_max=600,
            material_thickness_mm=3.0,
            layer_count=3,
            max_water_layers=0,  # disable capping for uniform test
        )
        assert config.layer_info(0)["type"] == "water"
        assert config.layer_info(1)["type"] == "mixed"
        assert config.layer_info(2)["type"] == "land"

    def test_max_water_layers_caps_water(self):
        config = calculate_layers(
            elevation_min=-3000,
            elevation_max=1500,
            material_thickness_mm=3.0,
            layer_count=10,
            max_water_layers=4,
        )
        bp = config.breakpoints()
        # Sea level (0.0) should be a breakpoint
        assert 0.0 in bp
        # Count water layers (layers entirely below 0)
        water_count = sum(
            1
            for i in range(config.layer_count)
            if config.layer_info(i)["type"] == "water"
        )
        assert water_count == 4
        # Remaining 6 layers should be land
        land_count = sum(
            1
            for i in range(config.layer_count)
            if config.layer_info(i)["type"] == "land"
        )
        assert land_count == 6
