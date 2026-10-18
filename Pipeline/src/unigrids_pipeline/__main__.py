"""Command line entry point: ``uv run unigrids-pipeline <step>``."""

from __future__ import annotations

import argparse
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
        if name == "fetch":
            step_parser.add_argument(
                "--source",
                help="Fetch one source only (nps, trails, padus, ridb, elevation, osm).",
            )

    subparsers.add_parser("all", help="Run every step in order.")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config.ensure_directories()

    requested = ORDER if args.step == "all" else (args.step,)
    for name in requested:
        function = STEP_FUNCTIONS[name]
        print(f"==> {name}")
        try:
            if name == "fetch":
                function(getattr(args, "source", None))
            else:
                function()
        except steps.StepNotBuiltError as error:
            print(f"    not built: {error}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
