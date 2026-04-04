#!/usr/bin/env python3
"""Compare generated 2D renders against reference images using SSIM.

Usage:
    python scripts/visual-regression-check.py --location kauai
    python scripts/visual-regression-check.py --all

Outputs JSON per location: {"location": "kauai", "ssim": 0.97, "pass": true}
Exit code: 0 if all pass, 2 if warnings, 1 if failures.
"""

import argparse
import json

# Thresholds (can be overridden via env vars)
import os
import sys
import tempfile
from pathlib import Path

SSIM_WARN = float(os.environ.get("VISUAL_REGRESSION_SSIM_WARN", "0.90"))
SSIM_FAIL = float(os.environ.get("VISUAL_REGRESSION_SSIM_FAIL", "0.85"))


def compare_location(location: str, ref_dir: Path) -> dict:
    """Generate a render for a location and compare to reference."""
    config_path = ref_dir / location / "config.json"
    reference_path = ref_dir / location / "render_2d.png"

    if not config_path.exists():
        return {"location": location, "error": "config.json not found", "pass": False}
    if not reference_path.exists():
        return {"location": location, "error": "render_2d.png not found", "pass": False}

    with open(config_path) as f:
        config = json.load(f)

    # Generate render to temp directory
    from topo2laser.contours.layer_calculator import resolve_thickness
    from topo2laser.elevation import BoundingBox
    from topo2laser.pipeline import PipelineConfig, run

    with tempfile.TemporaryDirectory() as tmpdir:
        output_dir = Path(tmpdir) / "output"
        pipeline_config = PipelineConfig(
            bbox=BoundingBox.from_string(config["bbox"]),
            output_dir=output_dir,
            material_thickness_mm=resolve_thickness(config["material_thickness"]),
            layer_count=config.get("layers"),
            water_layers=config.get("water_layers"),
            width_mm=float(config["width"].rstrip("mm")),
            high_res_land=config.get("high_res", False),
            include_frame=config.get("frame", True),
            render_2d=True,
        )
        run(pipeline_config)

        generated_path = output_dir / "render_2d.png"
        if not generated_path.exists():
            return {
                "location": location,
                "error": "render not generated",
                "pass": False,
            }

        # Compare using SSIM
        from skimage.io import imread
        from skimage.metrics import structural_similarity
        from skimage.transform import resize

        ref_img = imread(str(reference_path))
        gen_img = imread(str(generated_path))

        # Resize generated to match reference if dimensions differ
        if ref_img.shape != gen_img.shape:
            gen_img = resize(
                gen_img, ref_img.shape, anti_aliasing=True, preserve_range=True
            ).astype(ref_img.dtype)

        ssim = structural_similarity(ref_img, gen_img, channel_axis=-1)

    status = "pass" if ssim >= SSIM_WARN else "warn" if ssim >= SSIM_FAIL else "fail"
    return {
        "location": location,
        "ssim": round(ssim, 4),
        "status": status,
        "pass": bool(ssim >= SSIM_FAIL),
    }


def main():
    parser = argparse.ArgumentParser(description="Visual regression check")
    parser.add_argument("--location", help="Specific location to check")
    parser.add_argument("--all", action="store_true", help="Check all locations")
    args = parser.parse_args()

    project_root = Path(__file__).parent.parent
    ref_dir = project_root / "tests" / "reference"

    if args.location:
        locations = [args.location]
    elif args.all:
        locations = [d.name for d in ref_dir.iterdir() if d.is_dir()]
    else:
        parser.error("Provide --location or --all")

    results = []
    worst_exit = 0

    for loc in sorted(locations):
        result = compare_location(loc, ref_dir)
        results.append(result)
        print(json.dumps(result))

        if not result.get("pass", False):
            worst_exit = 1
        elif result.get("status") == "warn" and worst_exit < 1:
            worst_exit = 2

    sys.exit(worst_exit)


if __name__ == "__main__":
    main()
