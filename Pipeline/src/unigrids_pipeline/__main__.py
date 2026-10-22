"""Command line entry point: ``uv run unigrids-pipeline <step>``."""

from __future__ import annotations

import argparse
import dataclasses
import sys
from collections.abc import Sequence

from . import __version__, config, steps

STEP_FUNCTIONS = {
    "fetch": steps.fetch,
    "match": steps.match,
    "derive": steps.derive,
    "edit": steps.edit,
    "build": steps.build,
    "package": steps.package,
}

ORDER = ("fetch", "match", "derive", "edit", "build", "package")

# Steps that work on one park at a time, and so take --park.
PARK_STEPS = ("fetch", "derive", "build")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="unigrids-pipeline",
        description=(
            "Builds the reference data and offline packs that ship inside the Unigrids "
            "app. Not a server: the app never calls this."
        ),
    )
    parser.add_argument("--version", action="version", version=__version__)
    subparsers = parser.add_subparsers(dest="step", required=True)

    for name in ORDER:
        step_parser = subparsers.add_parser(
            name, help=(STEP_FUNCTIONS[name].__doc__ or "").strip().splitlines()[0]
        )
        if name in PARK_STEPS:
            _add_park_argument(step_parser)
        if name == "fetch":
            step_parser.add_argument(
                "--source",
                help=(
                    "Fetch one source only. Built: "
                    + ", ".join(steps.KEYLESS_SOURCES)
                    + ". Needs a key or is not built: "
                    + ", ".join(steps.KEYED_SOURCES)
                    + "."
                ),
            )
            step_parser.add_argument(
                "--refresh",
                action="store_true",
                help="Download again even if the source was already fetched today.",
            )
        if name == "build":
            defaults = config.DEFAULT_PACK_SETTINGS
            step_parser.add_argument(
                "--min-zoom", type=int, default=defaults.min_zoom, help="Shallowest tile zoom."
            )
            step_parser.add_argument(
                "--max-zoom", type=int, default=defaults.max_zoom, help="Deepest tile zoom."
            )
            step_parser.add_argument(
                "--tile-format",
                choices=("png", "png8", "webp"),
                default=defaults.tile_format,
                help="How tiles are encoded. The size report compares all three regardless.",
            )
            step_parser.add_argument(
                "--buffer-metres",
                type=float,
                default=defaults.boundary_buffer_m,
                help="How far outside the park boundary to render.",
            )
            step_parser.add_argument(
                "--skip-report",
                action="store_true",
                help="Build the pack without the all-parks extrapolation.",
            )

    reference_parser = subparsers.add_parser(
        "reference",
        help="Fetch and build the reference dataset the app bundles (places, guides, outlines).",
    )
    reference_parser.add_argument(
        "--refresh", action="store_true", help="Download again even if fetched today."
    )
    reference_parser.add_argument(
        "--skip-fetch",
        action="store_true",
        help="Build from the newest raw data already on disk, without touching the network.",
    )

    all_parser = subparsers.add_parser("all", help="Run every step in order.")
    _add_park_argument(all_parser)
    return parser


def _add_park_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--park",
        default=config.DEFAULT_PARK,
        help=f"NPS park code. Known: {', '.join(sorted(config.PARKS))}.",
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config.ensure_directories()

    if args.step == "reference":
        # Imported here so the pack steps never pay for the reference build's imports.
        from . import reference_build, reference_fetch

        print("==> reference fetch")
        if not args.skip_fetch:
            reference_fetch.fetch(refresh=args.refresh)
        print("==> reference build")
        reference_build.build(online=not args.skip_fetch)
        return 0

    requested = ORDER if args.step == "all" else (args.step,)
    park_code = getattr(args, "park", config.DEFAULT_PARK)

    for name in requested:
        function = STEP_FUNCTIONS[name]
        print(f"==> {name}")
        try:
            if name == "fetch":
                function(
                    getattr(args, "source", None),
                    park_code=park_code,
                    refresh=getattr(args, "refresh", False),
                )
            elif name == "derive":
                function(park_code=park_code)
            elif name == "build":
                function(
                    park_code=park_code,
                    settings=_pack_settings(args),
                    skip_report=getattr(args, "skip_report", False),
                )
            else:
                function()
        except steps.StepNotBuiltError as error:
            print(f"    not built: {error}", file=sys.stderr)
            # `all` is a convenience, not a contract: the steps that are built have
            # already done their work, and stopping here says which one is missing.
            return 2
    return 0


def _pack_settings(args: argparse.Namespace) -> config.PackSettings:
    """Pack settings from the command line, defaulting to the configured ones."""
    defaults = config.DEFAULT_PACK_SETTINGS
    return dataclasses.replace(
        defaults,
        min_zoom=getattr(args, "min_zoom", defaults.min_zoom),
        max_zoom=getattr(args, "max_zoom", defaults.max_zoom),
        tile_format=getattr(args, "tile_format", defaults.tile_format),
        boundary_buffer_m=getattr(args, "buffer_metres", defaults.boundary_buffer_m),
    )


if __name__ == "__main__":
    raise SystemExit(main())
