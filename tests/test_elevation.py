"""Tests for elevation data fetching."""

import pytest

from topo2laser.elevation.fetcher import BoundingBox
from topo2laser.elevation.sources import _tile_label, _tiles_for_bbox


class TestBoundingBox:
    def test_from_string(self):
        bbox = BoundingBox.from_string("21.8,-160.5,22.3,-159.2")
        assert bbox.south == 21.8
        assert bbox.west == -160.5
        assert bbox.north == 22.3
        assert bbox.east == -159.2

    def test_from_string_with_spaces(self):
        bbox = BoundingBox.from_string("21.8, -160.5, 22.3, -159.2")
        assert bbox.south == 21.8

    def test_invalid_south_north(self):
        with pytest.raises(ValueError, match="South.*must be less than north"):
            BoundingBox(south=23.0, west=-160.0, north=21.0, east=-159.0)

    def test_invalid_west_east(self):
        with pytest.raises(ValueError, match="West.*must be less than east"):
            BoundingBox(south=21.0, west=-159.0, north=23.0, east=-160.0)

    def test_wrong_part_count(self):
        with pytest.raises(ValueError, match="Expected 4"):
            BoundingBox.from_string("21.8,-160.5,22.3")

    def test_center(self):
        bbox = BoundingBox(south=20.0, west=-160.0, north=22.0, east=-158.0)
        assert bbox.center_lat == 21.0
        assert bbox.center_lon == -159.0


class TestTileLabel:
    def test_north_west(self):
        assert _tile_label(30, -165) == "N30W165"

    def test_south_east(self):
        assert _tile_label(-15, 45) == "S15E045"

    def test_zero_zero(self):
        assert _tile_label(0, 0) == "N00E000"


class TestTilesForBbox:
    def test_kauai_tiles(self):
        # Kaua'i: ~21.8N to 22.3N, 160.3W to 159.2W
        tiles = _tiles_for_bbox(21.8, -160.5, 22.3, -159.2)
        assert len(tiles) > 0
        # Should need the tile covering 15-30N, 165-150W
        assert "N30W165" in tiles

    def test_duluth_tiles(self):
        # Duluth: ~46.7N to 46.85N, 92.2W to 91.9W
        tiles = _tiles_for_bbox(46.7, -92.2, 46.85, -91.9)
        assert len(tiles) > 0

    def test_single_tile(self):
        # Small area within one tile
        tiles = _tiles_for_bbox(25.0, -160.0, 26.0, -159.0)
        assert len(tiles) >= 1
