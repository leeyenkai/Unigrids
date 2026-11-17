"""Canada's rules, kept apart from any download so they can be tested on their own: which
province and passport book a CPCAD record belongs to, which records are the second tier
and what they are called, which zone a place keeps, how Parks Canada's trail ratings,
facilities and attendance read.

Everything here reads CPCAD's and Parks Canada's fields as the services publish them and
never invents a value it does not find.
"""

from __future__ import annotations

import re
from typing import Any

# MARK: - Provinces and territories

# CPCAD's location codes (``LOC``) → ISO 3166-2:CA. Codes 14–21 are marine regions
# ("Coastal Pacific Marine"), which name no province.
LOCATIONS: dict[int, tuple[str, str]] = {
    1: ("AB", "Alberta"),
    2: ("BC", "British Columbia"),
    3: ("MB", "Manitoba"),
    4: ("NB", "New Brunswick"),
    5: ("NL", "Newfoundland and Labrador"),
    6: ("NT", "Northwest Territories"),
    7: ("NS", "Nova Scotia"),
    8: ("NU", "Nunavut"),
    9: ("ON", "Ontario"),
    10: ("PE", "Prince Edward Island"),
    11: ("QC", "Quebec"),
    12: ("SK", "Saskatchewan"),
    13: ("YT", "Yukon"),
}

# Province → passport book (ADR 0014). Wood Buffalo, which reaches into the Northwest
# Territories, is filed with the North by its content entry.
PASSPORT_REGION_OF: dict[str, str] = {
    **dict.fromkeys(("NB", "NS", "PE", "NL"), "atlantic"),
    "QC": "quebec",
    "ON": "ontario",
    **dict.fromkeys(("MB", "SK"), "prairies"),
    **dict.fromkeys(("AB", "BC"), "mountainsAndPacific"),
    **dict.fromkeys(("YT", "NT", "NU"), "north"),
}
PASSPORT_REGIONS = frozenset(PASSPORT_REGION_OF.values())

# Each province's main zone, as ``Subdivision.mainTimeZoneID`` in the app names it: the
# fallback for a place whose centre the zone lookup does not answer (a point at sea).
MAIN_TIME_ZONES: dict[str, str] = {
    "BC": "America/Vancouver", "AB": "America/Edmonton", "SK": "America/Regina",
    "MB": "America/Winnipeg", "ON": "America/Toronto", "QC": "America/Toronto",
    "NB": "America/Moncton", "NS": "America/Halifax", "PE": "America/Halifax",
    "NL": "America/St_Johns", "YT": "America/Whitehorse", "NT": "America/Yellowknife",
    "NU": "America/Iqaluit",
}

# The IANA zones that lie in Canada (and the two the tz database links into them): a
# lookup that answers anything else — an ocean's ``Etc/GMT+4`` — is not a Canadian zone.
CANADIAN_ZONES = frozenset({
    "America/St_Johns", "America/Halifax", "America/Glace_Bay", "America/Moncton",
    "America/Goose_Bay", "America/Blanc-Sablon", "America/Toronto", "America/Montreal",
    "America/Nipigon", "America/Thunder_Bay", "America/Iqaluit", "America/Pangnirtung",
    "America/Atikokan", "America/Coral_Harbour", "America/Winnipeg", "America/Rainy_River",
    "America/Resolute", "America/Rankin_Inlet", "America/Regina", "America/Swift_Current",
    "America/Edmonton", "America/Cambridge_Bay", "America/Yellowknife", "America/Inuvik",
    "America/Creston", "America/Dawson_Creek", "America/Fort_Nelson", "America/Whitehorse",
    "America/Dawson", "America/Vancouver",
})


def iso_code(location: Any) -> str | None:
    """CPCAD's ``LOC`` (``1``) → ``"AB"``; a marine region → None."""
    if isinstance(location, int | float) and int(location) in LOCATIONS:
        return LOCATIONS[int(location)][0]
    return None


def subdivision(code: str) -> str:
    """``"AB"`` → ``"CA-AB"``."""
    return f"CA-{code}"


def passport_region(code: str | None) -> str | None:
    return PASSPORT_REGION_OF.get(code or "")


def time_zone(found: str | None, codes: list[str]) -> str | None:
    """The zone a place keeps: the lookup's answer at its centre where that is a Canadian
    zone (Nunavut's parks keep Iqaluit's, Rankin Inlet's or Resolute's as they lie), else
    its first province's main zone."""
    if found in CANADIAN_ZONES:
        return found
    return MAIN_TIME_ZONES.get(codes[0]) if codes else None


# MARK: - CPCAD

PARKS_CANADA = 71
"""CPCAD's ``PROVIDER`` code for the Parks Canada Agency."""

# Parks Canada's records that make a national park, and the national marine
# conservation areas: the five Parks Canada lists, each keyed by its CPCAD parent, with the
# name and designation it gives them.
NATIONAL_PARK_TYPES = frozenset({"National Park", "National Park Reserve", "National Urban Park"})
MARINE_CONSERVATION_AREAS: dict[int, tuple[str, str]] = {
    711900000: ("Fathom Five", "National Marine Park"),
    714400000: (
        "Gwaii Haanas", "National Marine Conservation Area Reserve and Haida Heritage Site"
    ),
    715500000: ("Lake Superior", "National Marine Conservation Area"),
    718100000: ("Saguenay–St. Lawrence", "Marine Park"),
    718700000: ("Tallurutiup Imanga", "National Marine Conservation Area"),
}
MARINE_TYPES = frozenset({
    "National Marine Conservation Area", "National Marine Park", "Marine Park",
})
# The rows of Parks Canada's attendance table that are a marine area's own.
MARINE_ATTENDANCE: dict[int, str] = {
    711900000: "Fathom Five National Marine Park",
    718100000: "Saguenay-St. Lawrence Marine Park",
}

# CPCAD's designations that are a province's or territory's parks, and the designation
# the app shows beneath the name. British Columbia's Class A parks, Québec's parcs
# nationaux and Saskatchewan's natural environment and recreation parks are provincial
# parks by statute, whatever their names say (ADR 0014).
PROVINCIAL_TYPES: dict[str, str] = {
    "Provincial Park": "Provincial Park",
    "Wildland Provincial Park": "Wildland Provincial Park",
    "Wilderness Park": "Wilderness Park",
    "A - Park": "Provincial Park",
    "Quebec's national park": "Provincial Park",
    "Natural Environment Park": "Provincial Park",
    "Recreation Park": "Provincial Park",
    "Territorial Park": "Territorial Park",
}
MINIMUM_HECTARES = 10_000.0
"""The smallest provincial park the map carries: 100 km², by CPCAD's official area."""

# Words a provincial park's name ends in that are its designation, longest first.
_SUFFIXES = (
    ("Wildland Provincial Park", "Wildland Provincial Park"),
    ("Provincial Wilderness Park", "Wilderness Park"),
    ("Wilderness Provincial Park", "Wilderness Park"),
    ("Provincial Park", "Provincial Park"),
    ("Territorial Park", "Territorial Park"),
    ("Wilderness Park", "Wilderness Park"),
    ("Park", None),
)
_QUEBEC = re.compile(r"\s+National Park\s*\(Qu[ée]bec\)\s*$", re.IGNORECASE)
_CLASS = re.compile(r"\s*\((?:[A-Za-z ]+ Class|Recreation Class)\)\s*$")
_SMALL_WORDS = frozenset({"of", "the", "and", "de", "du", "des", "la", "le", "les", "à", "aux"})


def title_case(name: str) -> str:
    """CPCAD's capitals for British Columbia's parks ("HEIGHT OF THE ROCKIES PARK") as the
    park is written ("Height of the Rockies Park"). A name in mixed case is left alone."""
    if name != name.upper():
        return name

    def word(part: str, first: bool) -> str:
        lower = part.lower()
        if not first and lower in _SMALL_WORDS:
            return lower
        return "/".join(
            "-".join(
                "'".join(piece[:1].upper() + piece[1:] for piece in hyphened.split("'"))
                for hyphened in slashed.split("-")
            )
            for slashed in lower.split("/")
        )

    parts = name.split()
    return " ".join(word(part, index == 0) for index, part in enumerate(parts))


def display_name(name: str, type_e: str) -> tuple[str, str]:
    """``(name, designation)`` for a provincial or territorial park as the app shows it.

    "Cypress Hills Provincial Park" → ("Cypress Hills", "Provincial Park");
    "CAPE SCOTT PARK" (BC Class A) → ("Cape Scott", "Provincial Park");
    "Frontenac National Park (Québec)" → ("Frontenac", "Provincial Park");
    "Brightsand River Provincial Park (Waterway Class)" → ("Brightsand River", "Provincial
    Park"); "Tombstone" (Territorial Park) → ("Tombstone", "Territorial Park").
    """
    designation = PROVINCIAL_TYPES.get(type_e, "Provincial Park")
    # "KHUTZEYMATEEN PARK [A.K.A. KHUTZEYMATEEN/K'TZIM-A-DEEN GRIZZLY SANCTUARY]": the
    # bracket is a note on the record, not the name.
    text = re.sub(r"\s*\[[^\]]*\]\s*$", "", name.strip())
    text = re.sub(r"\s+", " ", title_case(text))
    text = _CLASS.sub("", text)
    if _QUEBEC.search(text):
        return _QUEBEC.sub("", text).strip(), "Provincial Park"
    for suffix, named in _SUFFIXES:
        if text.lower().endswith(" " + suffix.lower()):
            stem = text[: -len(suffix)].strip()
            if stem:
                return stem, named or designation
    # "Kitaskino Nuwenëné Wildland", as CPCAD shortens a wildland provincial park.
    if designation == "Wildland Provincial Park" and text.lower().endswith(" wildland"):
        return text[: -len(" wildland")].strip(), designation
    return text, designation


def identifier_names(name: str, designation: str) -> list[str]:
    """The names a place's identifier may be made from, best first: the whole name, then
    each part of a dual name, so "Mᑫuqʷin/Brooks Peninsula" is ``brooks-peninsula`` rather
    than refused. A wildland provincial park says so, as Alberta has a Castle Provincial
    Park beside its Castle Wildland."""
    suffix = " Wildland" if designation == "Wildland Provincial Park" else ""
    parts = [name, *(part.strip() for part in name.split("/") if part.strip())]
    return [f"{part}{suffix}" for part in dict.fromkeys(parts)]


def is_provincial_park(properties: dict[str, Any]) -> bool:
    return properties.get("TYPE_E") in PROVINCIAL_TYPES and properties.get("STATUS") != 0


def official_hectares(properties: dict[str, Any]) -> float | None:
    """CPCAD's official area (``O_AREA_HA``), or None where it records none."""
    value = properties.get("O_AREA_HA")
    try:
        hectares = float(value) if value is not None else None
    except (TypeError, ValueError):
        return None
    return hectares if hectares and hectares > 0 else None


# MARK: - Trails

TRAILS_DATASET_URL = "https://open.canada.ca/data/en/dataset/64a90e8d-5bc0-4027-8645-b5881b4068d4"
GRADE_PUBLISHER = "Parks Canada"
GRADE_SYSTEM = "parksCanadaDifficulty"

# Parks Canada's summer classification (``Summer_Classification_Été``), as the layer's own
# domain names it, and the band of the app's five each reads as. The bands are Unigrids'
# reading, not Parks Canada's.
DIFFICULTIES: dict[int, str] = {1: "Easy", 2: "Moderate", 3: "Difficult", 4: "Most difficult"}
BANDS: dict[str, str] = {
    "Easy": "easy",
    "Moderate": "moderate",
    "Difficult": "strenuous",
    "Most difficult": "veryStrenuous",
}

# ``General_Activity``: the layer repeats a line once for each activity it allows.
HIKING = 100
ACTIVITY_USES = {300: "Bicycle", 1300: "Horse"}
# ``Section_Type`` that no one walks.
NOT_WALKED = frozenset({8})  # cable car


def difficulty(code: Any) -> str | None:
    """``2`` → ``"Moderate"``; a code the domain does not name → None."""
    if isinstance(code, int | float) and int(code) in DIFFICULTIES:
        return DIFFICULTIES[int(code)]
    return None


def band(grade: str | None) -> str | None:
    """The app's difficulty band for a Parks Canada rating (``TrailDifficulty``'s raw value)."""
    return BANDS.get(grade or "")


def trail_grade(grade: str) -> dict[str, Any]:
    """A Parks Canada rating in the shape the app's ``TrailGrade`` takes."""
    return {
        "system": GRADE_SYSTEM,
        "grade": grade,
        "publisher": GRADE_PUBLISHER,
        "sourceURL": TRAILS_DATASET_URL,
    }


def trail_name(name: str | None) -> str:
    return re.sub(r"\s+", " ", (name or "").replace("\xa0", " ")).strip()


# MARK: - Facilities

# ``Facility_Type_Installation`` → the point of interest it is.
VISITOR_CENTRES = frozenset({1003, 7002})
FRONT_COUNTRY_CAMPING = 1001
BACKCOUNTRY_CAMPING = 3000
WARMING_HUT = 3001
TRAILHEAD = 1013
# ``Accommodation_Type`` 13, "Backcountry accommodation": huts and shelters.
BACKCOUNTRY_ACCOMMODATION = 13
ACCOMMODATION_TYPES: dict[int, str] = {
    1: "Camping", 2: "Group camping", 3: "oTENTik", 4: "MicrOcube", 5: "Oasis", 6: "Yurt",
    7: "Tipi", 8: "Historic stay", 9: "Cabin", 10: "Base camp", 11: "Mooring",
    12: "Backcountry camping", 13: "Backcountry accommodation",
}
_ROOFED = re.compile(r"\b(hut|shelter|cabin|refuge|lodge|chalet|abri)\b", re.IGNORECASE)


def facility_kind(properties: dict[str, Any]) -> str | None:
    """``visitorCentre``, ``campground`` or ``hut`` for a facility a visitor uses, else
    None. A backcountry camping or shelter area is a hut when its name says it has a
    roof ("Bryant Creek Shelter"), a campground otherwise."""
    kind = properties.get("Facility_Type_Installation")
    if kind in VISITOR_CENTRES:
        return "visitorCentre"
    if kind == FRONT_COUNTRY_CAMPING:
        return "campground"
    if kind == BACKCOUNTRY_CAMPING:
        return "hut" if _ROOFED.search(facility_name(properties) or "") else "campground"
    if kind == WARMING_HUT:
        return "hut"
    return None


# "Visitor center/Interpretation facility - Parc national de la mauricie (Saint-Mathieu)":
# the layer's kind and park before the place's own name.
_KIND_PARK_PLACE = re.compile(
    r"^(?P<kind>.+?)\s+-\s+Parc national [^()]+\((?P<place>[^()]+)\)$", re.IGNORECASE
)
_INTERPRETATION = re.compile(r"^visitor cent(?:er|re)\s*/\s*interpretation facility$",
                             re.IGNORECASE)
# Facilities the layer files as visitor centres that are a sign or a stage, and anything
# it marks closed.
_NOT_A_PLACE = re.compile(
    r"^(?:information boards?|amphitheatre|park orientation)$|\(closed\)", re.IGNORECASE
)


def facility_name(properties: dict[str, Any]) -> str | None:
    """The facility's English name as the layer writes it, with the layer's own kind and
    park taken off where they lead it ("Winter Warming Hut (Lac Étienne)", "Saint-Mathieu");
    None for a nameless one, a sign, a stage, or one marked closed."""
    name = re.sub(r"\s+", " ", (properties.get("Name_e") or "").replace("\xa0", " ")).strip()
    if match := _KIND_PARK_PLACE.match(name):
        kind, place = match.group("kind").strip(), match.group("place").strip()
        name = place if _INTERPRETATION.match(kind) else f"{kind} ({place})"
    if not name or _NOT_A_PLACE.search(name):
        return None
    return name


def facility_summary(properties: dict[str, Any], sites: dict[str, int] | None = None) -> str:
    """A facility's one line from Parks Canada's own record: what it is, then the kinds of
    site its campground offers, as the accommodation layer counts them under its name.
    "Front-country campground · 618 sites · 21 oTENTiks"."""
    kind = properties.get("Facility_Type_Installation")
    parts = [{
        FRONT_COUNTRY_CAMPING: "Front-country campground",
        BACKCOUNTRY_CAMPING: "Backcountry campground",
        WARMING_HUT: "Winter warming hut",
    }.get(kind, "Parks Canada visitor centre")]
    if kind == BACKCOUNTRY_CAMPING and _ROOFED.search(facility_name(properties) or ""):
        parts = ["Backcountry shelter"]
    # The accommodation layer counts a backcountry campground's pads as one point, so a
    # count is given for front-country campgrounds only.
    for label, count in (sites or {} if kind == FRONT_COUNTRY_CAMPING else {}).items():
        noun = "site" if label in ("Camping", "Backcountry camping") else label
        parts.append(f"{count} {noun}{'s' if count != 1 and not noun.endswith('s') else ''}")
    return " · ".join(parts)


def accommodation_counts(records: list[dict[str, Any]]) -> dict[str, int]:
    """How many sites of each kind a campground's accommodation records list, camping
    first."""
    counts: dict[str, int] = {}
    for record in records:
        label = ACCOMMODATION_TYPES.get(record.get("Accommodation_Type") or 0)
        if label:
            counts[label] = counts.get(label, 0) + 1
    order = list(ACCOMMODATION_TYPES.values())
    return dict(sorted(counts.items(), key=lambda item: order.index(item[0])))


def normal(name: str | None) -> str:
    """A name reduced for comparison: lower case, accents off, letters and digits only,
    without the words "campground", "camping" and "backcountry"."""
    text = (name or "").lower()
    for word in ("backcountry", "campground", "camping", "camp"):
        text = re.sub(rf"\b{word}\b", " ", text)
    folded = text.translate(str.maketrans("àâäçéèêëîïôöùûüÿ", "aaaceeeeiioouuuy"))
    return re.sub(r"[^a-z0-9]+", "", folded)


def official_url(url: Any) -> str | None:
    if isinstance(url, str) and url.startswith(
        ("https://parks.canada.ca/", "https://www.pc.gc.ca/", "https://pc.gc.ca/")
    ):
        return url.strip()
    return None


# MARK: - Attendance

ATTENDANCE_DATASET = "1e2bd6b2-d6c7-415b-8c95-f5f6b2459759"
ATTENDANCE_URL = (
    "https://open.canada.ca/data/dataset/1e2bd6b2-d6c7-415b-8c95-f5f6b2459759/resource/"
    "73609a87-77f6-4a69-bd96-b8e3f3451aa7/download/parks-canada-attendance-2025_26.csv"
)
ATTENDANCE_FISCAL_YEAR = (2025, 2026)
"""Parks Canada counts by fiscal year, 1 April to 31 March: 2025–26 is the latest."""


def attendance_period(fiscal: tuple[int, int] = ATTENDANCE_FISCAL_YEAR) -> str:
    first, last = fiscal
    return f"Parks Canada fiscal year {first}–{str(last)[-2:]} (April {first} – March {last})"


def attendance(rows: list[list[str]]) -> dict[str, int]:
    """Place → its count, from the table's rows. A cell that is not a count ("UR", under
    review) leaves the place out rather than reading as zero."""
    found: dict[str, int] = {}
    for row in rows[1:]:
        if len(row) < 2:
            continue
        place = re.sub(r"\s+", " ", row[0]).strip()
        figure = row[1].replace(",", "").replace("\xa0", "").strip()
        if place and figure.isdigit():
            found[place] = int(figure)
    return found


# MARK: - Documents


def document_kind(title: str, url: str) -> str:
    text = f"{title} {url.rsplit('/', 1)[-1]}".lower()
    if "map" in text or "carte" in text:
        return "map"
    if any(word in text for word in ("guide", "brochure", "visitor", "depliant", "newspaper")):
        return "brochure"
    return "other"


def is_french(url: str, title: str = "") -> bool:
    """A PDF in French, when the page links both: "_FR.pdf", "-fr-", "(French)"."""
    stem = url.rsplit("/", 1)[-1].lower()
    return bool(
        re.search(r"(^|[-_ .])(fr|fra|french|francais)([-_ .]|$)", stem)
        or re.search(r"\b(french|français|francais)\b", title.lower())
    )
