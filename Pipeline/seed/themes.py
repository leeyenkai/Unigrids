"""Theme tags for the pilot seed.

Themes drive the "themes and landscapes" stats family (SPECIFICATION.md §11).
The pipeline will seed these from NPS API topics and activities and curate them;
this set is hand-assigned and covers only the obvious cases, which is why the
stats page shows a theme only when at least one park carries it.

The volcanic set is deliberately the six the specification's own example counts
("4 of 6 volcanic parks seen").
"""

THEMES = [
    ("canyons", "geology", "Canyons"),
    ("volcanoes", "geology", "Volcanoes"),
    ("glaciers", "geology", "Glaciers"),
    ("caves", "geology", "Caves"),
    ("dunes", "geology", "Dunes"),
    ("hot-springs", "geology", "Geothermal"),
    ("fossils", "geology", "Fossils"),
    ("mountains", "geology", "Mountains"),
    ("desert", "ecosystem", "Desert"),
    ("alpine", "ecosystem", "Alpine"),
    ("temperate-rainforest", "ecosystem", "Temperate rainforest"),
    ("deciduous-forest", "ecosystem", "Deciduous forest"),
    ("coral-reef", "ecosystem", "Coral reef"),
    ("wetland", "ecosystem", "Wetland"),
    ("coastal", "ecosystem", "Coastal"),
    ("tundra", "ecosystem", "Tundra"),
    ("indigenous-heritage", "history", "Indigenous heritage"),
    ("conservation-movement", "history", "Conservation movement"),
]

# theme slug -> park slugs
THEME_PARKS = {
    "canyons": [
        "grand-canyon", "zion", "bryce-canyon", "canyonlands",
        "black-canyon-of-the-gunnison",
    ],
    "volcanoes": [
        "hawaii-volcanoes", "haleakala", "lassen-volcanic", "crater-lake",
        "yellowstone", "katmai",
    ],
    "glaciers": [
        "glacier", "glacier-bay", "kenai-fjords", "mount-rainier",
        "north-cascades", "wrangell-st-elias", "denali", "olympic",
    ],
    "caves": ["carlsbad-caverns", "mammoth-cave", "wind-cave", "great-basin"],
    "dunes": ["great-sand-dunes", "white-sands", "indiana-dunes"],
    "hot-springs": ["yellowstone", "hot-springs", "lassen-volcanic"],
    "fossils": ["petrified-forest", "badlands", "theodore-roosevelt"],
    "mountains": [
        "rocky-mountain", "grand-teton", "glacier", "mount-rainier",
        "north-cascades", "great-smoky-mountains", "shenandoah", "denali",
        "wrangell-st-elias", "guadalupe-mountains",
    ],
    "desert": [
        "death-valley", "joshua-tree", "saguaro", "big-bend", "arches",
        "canyonlands", "capitol-reef", "petrified-forest", "white-sands",
    ],
    "alpine": [
        "rocky-mountain", "grand-teton", "glacier", "mount-rainier",
        "north-cascades", "sequoia", "kings-canyon", "yosemite",
        "great-basin", "denali",
    ],
    "temperate-rainforest": ["olympic", "redwood"],
    "deciduous-forest": [
        "great-smoky-mountains", "shenandoah", "new-river-gorge",
        "cuyahoga-valley", "mammoth-cave", "congaree", "acadia",
    ],
    "coral-reef": ["biscayne", "dry-tortugas", "virgin-islands", "american-samoa"],
    "wetland": ["everglades", "congaree", "voyageurs", "biscayne"],
    "coastal": [
        "acadia", "channel-islands", "olympic", "redwood", "biscayne",
        "dry-tortugas", "virgin-islands", "american-samoa", "kenai-fjords",
        "glacier-bay", "indiana-dunes",
    ],
    "tundra": [
        "denali", "gates-of-the-arctic", "kobuk-valley", "rocky-mountain",
        "wrangell-st-elias",
    ],
    "indigenous-heritage": [
        "mesa-verde", "petrified-forest", "canyonlands", "great-smoky-mountains",
        "hawaii-volcanoes", "haleakala", "american-samoa",
    ],
    "conservation-movement": [
        "yellowstone", "yosemite", "theodore-roosevelt", "acadia",
        "great-smoky-mountains", "redwood",
    ],
}

_slugs = {t[0] for t in THEMES}
assert set(THEME_PARKS) <= _slugs, set(THEME_PARKS) - _slugs
