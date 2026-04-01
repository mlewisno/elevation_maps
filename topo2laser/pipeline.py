"""Pipeline orchestration — connects all stages."""

from dataclasses import dataclass
from pathlib import Path


@dataclass
class PipelineConfig:
    """Configuration for a full pipeline run."""

    bbox: tuple[float, float, float, float]  # south, west, north, east
    layer_count: int
    output_dir: Path
    width_mm: float = 300.0
    height_mm: float | None = None  # auto-calculated from aspect ratio
    material_thickness_mm: float = 3.0
    kerf_mm: float = 0.2
    include_landmarks: bool = False
    alignment: str = "engraved-outline"
    vertical_exaggeration: float = 1.0


def run(config: PipelineConfig) -> None:
    """Execute the full pipeline."""
    raise NotImplementedError("Pipeline stages not yet implemented")
