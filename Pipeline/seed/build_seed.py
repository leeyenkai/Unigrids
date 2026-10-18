#!/usr/bin/env python3
"""Write the hand-authored pilot seed into the app's reference resources.

This is **not** the data pipeline. It is a stopgap so the app has real places to
render while `Pipeline/src/unigrids_pipeline` is built, and it should be deleted
once the pipeline's build step produces `manifest.json`, `places.json`,
`pois.json`, `themes.json` and `guides/*.json` for itself.

Guide content is NOT written from here: the four pilot guides are hand-edited
JSON under the output directory and are left alone.

    python3 Pipeline/seed/build_seed.py
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from parks import PARKS
from pois import POIS
from themes import THEME_PARKS, THEMES

OUT = (
    Path(__file__).resolve().parents[2]
    / "Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference"
)

PILOT = ("zion", "acadia", "yellowstone", "great-smoky-mountains")

# At-a-glance figures for the pilot parks only (SPECIFICATION.md §6, panel 3).
# Hand-authored and UNVERIFIED: visitation is rounded to the nearest hundred
# thousand precisely so it does not read as a precise published figure. The
# pipeline's fetch step replaces all of it from the NPS API. Every other park
# ships with no facts at all, which renders as absent rather than as a guess.
FACTS = {
    "zion": {
        "establishedYear": 1919,
        "areaAcres": 147237,
        "lowestElevationMetres": 1117,
        "highestElevationMetres": 2660,
        "annualVisits": 4_600_000,
        "annualVisitsYear": 2023,
        "entranceFee": "$35 per vehicle, valid 7 days",
        "bestSeasons": ["spring", "autumn"],
        "suggestedTime": "Two to three days",
    },
    "acadia": {
        "establishedYear": 1919,
        "areaAcres": 49075,
        "lowestElevationMetres": 0,
        "highestElevationMetres": 466,
        "annualVisits": 3_900_000,
        "annualVisitsYear": 2023,
        "entranceFee": "$35 per vehicle, valid 7 days",
        "bestSeasons": ["summer", "autumn"],
        "suggestedTime": "Two to three days",
    },
    "yellowstone": {
        "establishedYear": 1872,
        "areaAcres": 2_219_791,
        "lowestElevationMetres": 1610,
        "highestElevationMetres": 3462,
        "annualVisits": 4_500_000,
        "annualVisitsYear": 2023,
        "entranceFee": "$35 per vehicle, valid 7 days",
        "bestSeasons": ["summer", "autumn"],
        "suggestedTime": "Four to five days",
    },
    "great-smoky-mountains": {
        "establishedYear": 1934,
        "areaAcres": 522_427,
        "lowestElevationMetres": 267,
        "highestElevationMetres": 2025,
        "annualVisits": 13_300_000,
        "annualVisitsYear": 2023,
        "entranceFee": "No entrance fee; a parking tag is required to park for "
                       "more than 15 minutes",
        "bestSeasons": ["spring", "autumn"],
        "suggestedTime": "Three to four days",
    },
}

# Approximate park extents, for framing the map camera.
EXTENTS = {
    "zion": (37.12, -113.25, 37.52, -112.85),
    "acadia": (44.05, -68.55, 44.45, -68.00),
    "yellowstone": (44.13, -111.15, 45.11, -109.82),
    "great-smoky-mountains": (35.43, -84.00, 35.80, -83.00),
}


def park_themes(slug: str) -> list[str]:
    return sorted(
        f"theme-{theme}" for theme, parks in THEME_PARKS.items() if slug in parks
    )


def build_places() -> list[dict]:
    places = []
    for slug, name, designation, states, lat, lon, code in PARKS:
        place: dict = {
            "id": f"np-{slug}",
            "name": name,
            "designation": designation,
            "kind": "nationalPark",
            "agency": "nps",
            "states": states,
            "centre": {"latitude": lat, "longitude": lon},
            "npsParkCode": code,
            "themes": park_themes(slug),
            "officialURL": f"https://www.nps.gov/{code.lower()}/",
        }
        if slug in EXTENTS:
            south, west, north, east = EXTENTS[slug]
            place["extent"] = {
                "south": south, "west": west, "north": north, "east": east,
            }
        if slug in FACTS:
            place["facts"] = FACTS[slug]
        places.append(place)
    return places


def build_pois() -> list[dict]:
    rows = []
    for slug, poi, kind, name, lat, lon, rank, summary, stamp in POIS:
        rows.append({
            "id": f"poi-{slug}-{poi}",
            "placeID": f"np-{slug}",
            "kind": kind,
            "name": name,
            "location": {"latitude": lat, "longitude": lon},
            "rank": rank,
            "summary": summary,
            "hasStamp": stamp,
        })
    return rows


def build_themes() -> list[dict]:
    return [
        {"id": f"theme-{slug}", "family": family, "name": name}
        for slug, family, name in THEMES
    ]


def write(name: str, payload: object) -> None:
    path = OUT / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {path.relative_to(OUT.parents[4])}")


def built_on(refresh: bool) -> str:
    """The manifest's build date, kept stable unless asked to refresh.

    Re-running this script must produce byte-identical output, or CI's "the seed
    regenerates identically" check fails for no reason the next day. So the existing
    date is preserved and only ``--refresh-date`` moves it.
    """
    existing = OUT / "manifest.json"
    if not refresh and existing.exists():
        try:
            return str(json.loads(existing.read_text())["builtOn"])
        except (ValueError, KeyError):
            pass
    return date.today().isoformat()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--refresh-date",
        action="store_true",
        help="Stamp the manifest with today's date instead of keeping the existing one.",
    )
    args = parser.parse_args()

    write("manifest", {
        "version": 1,
        "builtOn": built_on(args.refresh_date),
        "provenance": "seed",
        "note": (
            "Hand-authored pilot seed. All 63 national parks by name, state and "
            "approximate centre; deep content for Zion, Acadia, Yellowstone and "
            "Great Smoky Mountains. Figures are unverified and are replaced by the "
            "data pipeline."
        ),
    })
    write("places", build_places())
    write("pois", build_pois())
    write("themes", build_themes())
    missing = [p for p in PILOT if not (OUT / "guides" / f"np-{p}.json").exists()]
    if missing:
        print(f"note: no guide file yet for {', '.join(missing)}")


if __name__ == "__main__":
    main()
