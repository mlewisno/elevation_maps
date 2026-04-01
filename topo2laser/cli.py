"""CLI entry point for topo2laser."""

import click


@click.command()
@click.option(
    "--bbox",
    required=True,
    help="Bounding box as 'south,west,north,east' in decimal degrees.",
)
@click.option("--layers", default=8, help="Number of elevation layers.")
@click.option("--width", default="300mm", help="Physical width of output.")
@click.option("--height", default=None, help="Physical height (auto if omitted).")
@click.option(
    "--material-thickness", default="3mm", help="Thickness of each layer's material."
)
@click.option("--kerf", default="0.2mm", help="Laser kerf width for compensation.")
@click.option("--landmarks/--no-landmarks", default=False, help="Include landmark labels.")
@click.option(
    "--alignment",
    type=click.Choice(["dowel-holes", "engraved-outline", "none"]),
    default="engraved-outline",
    help="Alignment strategy between layers.",
)
@click.option("--exaggeration", default=1.0, help="Vertical exaggeration factor.")
@click.option("--output", "-o", required=True, help="Output directory for SVGs.")
def main(bbox, layers, width, height, material_thickness, kerf, landmarks,
         alignment, exaggeration, output):
    """Convert geographic elevation data to laser-cuttable SVG layers."""
    click.echo(f"topo2laser v0.1.0")
    click.echo(f"Bounding box: {bbox}")
    click.echo(f"Layers: {layers}")
    click.echo(f"Output: {output}")
    click.echo("Pipeline not yet implemented — see .specs/features/FEAT-001")


if __name__ == "__main__":
    main()
