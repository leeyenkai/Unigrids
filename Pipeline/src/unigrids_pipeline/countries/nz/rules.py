"""New Zealand's rules, kept apart from any download so they can be tested on their own:
which region and passport book a place belongs to, which Public Conservation Land records
are the second tier and what they are called, how DOC's track categories read, and how a
hut or campsite is described.

Everything here reads DOC's and Stats NZ's fields as the services publish them and never
invents a value it does not find.
"""

from __future__ import annotations

import re
from typing import Any

# MARK: - Regions

# Stats NZ's regional council codes (REGC) → ISO 3166-2:NZ. ``Subdivision`` in the app
# carries the same sixteen regions and the Chatham Islands Territory; a code it does not
# know is dropped there, never shown. Stats NZ's "99, Area Outside Region" is the Chatham
# Islands and the subantarctic islands: only a point east of 180° is the Chathams.
REGIONS: dict[str, tuple[str, str]] = {
    "01": ("NTL", "Northland"),
    "02": ("AUK", "Auckland"),
    "03": ("WKO", "Waikato"),
    "04": ("BOP", "Bay of Plenty"),
    "05": ("GIS", "Gisborne"),
    "06": ("HKB", "Hawke's Bay"),
    "07": ("TKI", "Taranaki"),
    "08": ("MWT", "Manawatū-Whanganui"),
    "09": ("WGN", "Wellington"),
    "12": ("WTC", "West Coast"),
    "13": ("CAN", "Canterbury"),
    "14": ("OTA", "Otago"),
    "15": ("STL", "Southland"),
    "16": ("TAS", "Tasman"),
    "17": ("NSN", "Nelson"),
    "18": ("MBH", "Marlborough"),
}
OUTSIDE_REGION = "99"
CHATHAM = "CIT"

# Region → passport book (ADR 0014): North Island; Upper South Island (Nelson Tasman,
# Marlborough, the West Coast and Canterbury); Lower South Island and Rakiura (Otago and
# Southland). The Chatham Islands belong to none of the three.
PASSPORT_REGION_OF: dict[str, str] = {
    **dict.fromkeys(("NTL", "AUK", "WKO", "BOP", "GIS", "HKB", "TKI", "MWT", "WGN"),
                    "northIsland"),
    **dict.fromkeys(("TAS", "NSN", "MBH", "WTC", "CAN"), "upperSouthIsland"),
    **dict.fromkeys(("OTA", "STL"), "lowerSouthIsland"),
}
PASSPORT_REGIONS = frozenset(PASSPORT_REGION_OF.values())

MAINLAND_TIME_ZONE = "Pacific/Auckland"
CHATHAM_TIME_ZONE = "Pacific/Chatham"


def iso_code(regc: str | None, longitude: float | None = None) -> str | None:
    """``"13"`` → ``"CAN"``; Stats NZ's area outside any region is the Chathams only east
    of 180° (west of −175°, as longitudes are written), and otherwise no region at all."""
    code = (regc or "").strip().zfill(2)
    if code in REGIONS:
        return REGIONS[code][0]
    if code == OUTSIDE_REGION and longitude is not None and (longitude < -175 or longitude > 180):
        return CHATHAM
    return None


def subdivision(code: str) -> str:
    """``"CAN"`` → ``"NZ-CAN"``."""
    return f"NZ-{code}"


def passport_region(code: str | None) -> str | None:
    return PASSPORT_REGION_OF.get(code or "")


def time_zone(codes: list[str]) -> str:
    """The zone a place keeps: the Chathams' own, 45 minutes ahead, or the mainland's."""
    return CHATHAM_TIME_ZONE if codes and codes[0] == CHATHAM else MAINLAND_TIME_ZONE


# MARK: - The second tier

NATIONAL_PARK_SECTION = "S4_NATIONAL_PARK"
CONSERVATION_PARK_SECTION = "S19_CONSERVATION_PARK"

# The smallest conservation park the map carries, in square metres (5 km²). DOC records
# the access strips and outlying parcels of a park as conservation parks of their own
# ("Wires Road Access", 800 m²); the threshold keeps the places a visitor plans a day
# around. Sugar Loaf Islands (7 km²) is the smallest named park above it.
MINIMUM_AREA_M2 = 5_000_000

# "Conservation Park - North West Nelson Forest Park - Takaka River - Cobb Dam Road" is a
# parcel of North-west Nelson Forest Park, not a park of its own.
_PARCEL = re.compile(r"^Conservation Park\s*-\s*(?P<rest>.+)$", re.IGNORECASE)
# "Waipoua Forest (Pt Northland Conservation Park)": one forest of the twenty that make up
# Northland Conservation Park, each a place a visitor goes to by its own name.
_PART_OF = re.compile(r"\s*\(\s*pt\.?\s+(?P<park>[^)]+?)\s*\)\s*$", re.IGNORECASE)
_DESIGNATIONS = (("Forest Park", "Forest Park"), ("Conservation Park", "Conservation Park"))


def normal(name: str) -> str:
    """A name reduced for comparison: lower case, letters and digits only, hyphens and
    case ignored ("North-west Nelson" and "North West Nelson" agree)."""
    folded = name.lower().replace("ō", "o").replace("ū", "u").replace("ā", "a")
    folded = folded.replace("ē", "e").replace("ī", "i")
    return re.sub(r"[^a-z0-9]+", "", folded)


def is_parcel(name: str) -> bool:
    """Whether a record is a parcel named after the park it belongs to."""
    return bool(_PARCEL.match(name.strip()))


def parent_of(name: str, park_names: list[str]) -> str | None:
    """The park a parcel record belongs to: the longest park name its own name begins
    with after "Conservation Park - ", or None for a record that is a park itself."""
    match = _PARCEL.match(name.strip())
    if not match:
        return None
    rest = normal(match.group("rest"))
    found = [park for park in park_names if normal(park) and rest.startswith(normal(park))]
    return max(found, key=len) if found else None


def display_name(name: str) -> tuple[str, str]:
    """``(name, designation)`` for a conservation park as the app shows it, the
    designation taken off the name where the name ends in it.

    "Kaimanawa Forest Park" → ("Kaimanawa", "Forest Park"); "Ahuriri Conservation Park"
    → ("Ahuriri", "Conservation Park"); "Waipoua Forest (Pt Northland Conservation Park)"
    → ("Waipoua Forest", "Conservation Park"); a name that ends in neither keeps its
    whole self, under its legal designation ("Korowai/Torlesse Tussocklands Park").
    """
    text = re.sub(r"\s+", " ", name).strip()
    if match := _PART_OF.search(text):
        return text[: match.start()].strip(), "Conservation Park"
    for suffix, designation in _DESIGNATIONS:
        if text.lower().endswith(" " + suffix.lower()):
            return text[: -len(suffix)].strip(), designation
    return text, "Conservation Park"


def part_of(name: str) -> str | None:
    """"Waipoua Forest (Pt Northland Conservation Park)" → "Northland Conservation
    Park"; None for a park that is whole in itself."""
    match = _PART_OF.search(name)
    if not match:
        return None
    park = re.sub(r"\bCons\.?(?=\s|$)", "Conservation", match.group("park"))
    return re.sub(r"\s+", " ", park).strip()


def recorded_hectares(properties: dict[str, Any]) -> float | None:
    """DOC's recorded area (``Recorded_Area``, hectares), or None where it records none.
    The GIS area is not offered in its place: it is a drawing's area, not the record's."""
    value = properties.get("Recorded_Area")
    try:
        hectares = float(value) if value is not None else None
    except (TypeError, ValueError):
        return None
    return hectares if hectares and hectares > 0 else None


def gis_area_m2(properties: dict[str, Any]) -> float:
    """The outline's area as the service measures it (NZTM metres), for the threshold."""
    try:
        return float(properties.get("Shape__Area") or 0.0)
    except (TypeError, ValueError):
        return 0.0


# MARK: - Tracks

TRACK_CATEGORIES_URL = (
    "https://www.doc.govt.nz/parks-and-recreation/things-to-do/walking-and-tramping/"
    "track-categories/"
)
GRADE_PUBLISHER = "Department of Conservation"

# DOC's six walking track categories, as its track-categories page names them, and the
# band of the app's five that each reads as. The bands are Unigrids' reading, not DOC's.
CATEGORIES: dict[str, str] = {
    "Wheelchair-accessible short walk": "easy",
    "Easy short walk": "easy",
    "Easy to intermediate walking track": "moderate",
    "Intermediate tramping track": "moderatelyStrenuous",
    "Advanced tramping track": "strenuous",
    "Expert route": "veryStrenuous",
}

# The labels the DOC Tracks layer still carries — its web category (``WEB_CATEGORY_TRACK``)
# and its asset class (``SubObjectType``) — → the current category.
_LEGACY: dict[str, str] = {
    "easy access (wheelchair)": "Wheelchair-accessible short walk",
    "short walk (disabled)": "Wheelchair-accessible short walk",
    "short walk": "Easy short walk",
    "walking track": "Easy to intermediate walking track",
    "great walk/easy tramping track": "Intermediate tramping track",
    "great walk": "Intermediate tramping track",
    "easy tramping track": "Intermediate tramping track",
    "tramping track": "Advanced tramping track",
    "route": "Expert route",
}

# Asset classes that are not walking tracks.
NOT_WALKS = frozenset({"cycle track", "pavement"})


def track_category(web_category: str | None, asset_class: str | None = None) -> str | None:
    """The current DOC category for a track record: its web category first, then its
    asset class; None for a record that carries neither in a form DOC uses."""
    for label in (web_category, asset_class):
        text = re.sub(r"\s+", " ", (label or "")).strip().lower()
        if text in _LEGACY:
            return _LEGACY[text]
        for category in CATEGORIES:
            if text == category.lower():
                return category
    return None


def band(category: str | None) -> str | None:
    """The app's difficulty band for a DOC category (``TrailDifficulty``'s raw value)."""
    return CATEGORIES.get(category or "")


def track_grade(category: str) -> dict[str, Any]:
    """A DOC category in the shape the app's ``TrailGrade`` takes."""
    return {
        "system": "newZealandTrackCategory",
        "grade": category,
        "publisher": GRADE_PUBLISHER,
        "sourceURL": TRACK_CATEGORIES_URL,
    }


def dogs_allowed(values: list[str | None]) -> bool | None:
    """Whether dogs may walk a track, where every record of it says the same: "No Dogs"
    is no; "on a leash" and "under control" are yes; a permit for hunting dogs, a mix,
    or silence leaves it unsaid."""
    answers: set[bool] = set()
    for value in values:
        parts = {part.strip().lower() for part in (value or "").split(",") if part.strip()}
        if not parts:
            return None
        if parts == {"no dogs"}:
            answers.add(False)
        elif parts <= {"dogs on a leash only", "dogs allowed - under control"}:
            answers.add(True)
        else:
            return None
    return answers.pop() if len(answers) == 1 else None


_ABBREVIATIONS = ((re.compile(r"\bTk\b\.?"), "Track"), (re.compile(r"\bTrk\b\.?"), "Track"))
_ASSET_PREFIX = re.compile(r"^\s*T3\s*:\s*", re.IGNORECASE)


def track_name(name: str | None) -> str:
    """A track's name as the layer records it, with DOC's asset-register prefix ("T3:")
    off and its abbreviation for track spelled out; nothing else is rewritten, since
    the rest of a shortened name ("Clinton Hut Jcn") cannot be expanded without guessing."""
    text = _ASSET_PREFIX.sub("", name or "")
    for pattern, word in _ABBREVIATIONS:
        text = pattern.sub(word, text)
    return re.sub(r"\s+", " ", text).strip()


# "Milford Tk - Clinton Hut Jcn To Bus Stop": the track, then the section. A dash with a
# space on at least one side, so a hyphenated name ("Te Papa-Kura") is not split.
_SECTION = re.compile(r"^(?P<base>.+?)(?:\s+-\s*|\s*-\s+)(?P<section>.+)$")


# Words that name no track when they stand before the dash ("Track - Maori Beach To Port
# William"): the section after it is the record's name.
_GENERIC = frozenset({"track", "walk", "route", "tramping track", "walking track"})

# DOC's own abbreviations for its best-known tracks, as they open a section's name
# ("Atct - Marahau To Inland Track Junction" is a section of the Abel Tasman Coast Track,
# whose site is ABTASCOT). Spelled out only when one is the whole of a track's name.
TRACK_ABBREVIATIONS = {
    "atct": "Abel Tasman Coast Track",
    "tac": "Tongariro Alpine Crossing",
    "tnc": "Tongariro Northern Circuit",
    "rtmt": "Round the Mountain Track",
    "amc": "Around the Mountain Circuit",
}


def track_base(name: str) -> str | None:
    """The track a section record names before its dash ("Milford Track" for "Milford
    Track - Clinton Hut Jcn To Bus Stop"), or None for a name with no section or one
    whose first part names no track ("Track - Maori Beach To Port William")."""
    match = _SECTION.match(name)
    if not match:
        return None
    base = match.group("base").strip()
    if len(base) < 3 or base.lower() in _GENERIC:
        return None
    return TRACK_ABBREVIATIONS.get(base.lower(), base)


def without_generic_prefix(name: str) -> str:
    """"Track - Maori Beach To Port William" → "Maori Beach To Port William": DOC's own
    words for the section, without the word that names nothing."""
    match = _SECTION.match(name)
    if match and match.group("base").strip().lower() in _GENERIC:
        return match.group("section").strip()
    return name


def site_of(floc_id: str | None) -> str:
    """``"MILFRDTK-TK03"`` → ``"MILFRDTK"``: DOC's site code, which every section of a
    track shares."""
    return re.split(r"-TK|-TP", floc_id or "", maxsplit=1)[0]


# MARK: - Huts, campsites and visitor centres

# Records the asset layers mark as closed, being built or removed.
OPEN = "OPEN"


def is_open_to_the_public(properties: dict[str, Any]) -> bool:
    """A DOC asset that is open and in public use, by the layer's own two fields."""
    return (
        (properties.get("CharValue2") or "").strip().upper() == OPEN
        and (properties.get("CharValue14") or "").strip().lower() == "yes"
    )


def characteristic(properties: dict[str, Any], name: str) -> str | None:
    """The value DOC's asset layers file under a named characteristic: ``CharNameN`` holds
    the name and ``CharValueN`` the value, in an order that differs between layers."""
    for key, value in properties.items():
        if key.startswith("CharName") and value == name:
            found = properties.get("CharValue" + key.removeprefix("CharName"))
            return str(found).strip() if found not in (None, "") else None
    return None


def _count(text: str | None) -> int | None:
    match = re.search(r"\d+", text or "")
    return int(match.group(0)) if match else None


def hut_summary(properties: dict[str, Any], web: dict[str, Any] | None = None) -> str | None:
    """A hut's one line from DOC's own record: its category, its bunks, and whether it is
    booked ahead. "Great Walk Hut · 40 bunks · Bookable"."""
    parts: list[str] = []
    category = (properties.get("SubObjectType") or "").strip()
    # Asset codes ("BUIIN-BUIN") stand where a few records have no category.
    if category and not re.fullmatch(r"[A-Z]+-[A-Z]+", category):
        parts.append(category)
    if (bunks := _count(characteristic(properties, "WEB_HUT_BUNKS"))) is not None:
        parts.append(f"{bunks} bunk{'s' if bunks != 1 else ''}")
    if (web or {}).get("bookable", "").strip().lower() == "yes":
        parts.append("Bookable")
    return " · ".join(parts) or None


def campsite_summary(
    properties: dict[str, Any], web: dict[str, Any] | None = None
) -> str | None:
    """A campsite's one line: DOC's category, its sites, and whether it is booked ahead.
    "Great Walk campsite · 15 sites · Bookable"."""
    parts: list[str] = []
    category = properties.get("SubObjectType") or characteristic(properties, "WEB_CATEGORY_CAMP")
    if (category := (category or "").strip()) and not re.fullmatch(r"[A-Z]+-[A-Z]+", category):
        parts.append(f"{category} campsite")
    sites = sum(
        number
        for name in ("WEB_NUM_SITES_NON_POWER", "WEB_NUM_SITES_POWER")
        if (number := _count(characteristic(properties, name)))
    )
    if sites:
        parts.append(f"{sites} site{'s' if sites != 1 else ''}")
    if (web or {}).get("bookable", "").strip().lower() == "yes":
        parts.append("Bookable")
    return " · ".join(parts) or None
