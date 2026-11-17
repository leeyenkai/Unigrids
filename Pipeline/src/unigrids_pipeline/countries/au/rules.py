"""Australia's rules, kept apart from any download so they can be tested on their own:
which state or territory and passport book a place belongs to, which CAPAD records make a
park and what it is called, which date, area and agency CAPAD's fields give, which zone a
place keeps, and how Queensland's track classes read.

Everything here reads CAPAD's, the ABS's and Queensland's fields as the services publish
them and never invents a value it does not find.
"""

from __future__ import annotations

import re
from typing import Any

# MARK: - States and territories

# The ABS's state and territory codes (ASGS Edition 3, ``state_code_2021``) → the app's
# codes. "9, Other Territories" is Jervis Bay, Christmas Island, the Cocos (Keeling)
# Islands and Norfolk Island together; ``other_territory`` tells them apart.
ABS_STATES: dict[str, str] = {
    "1": "NSW", "2": "VIC", "3": "QLD", "4": "SA", "5": "WA", "6": "TAS", "7": "NT",
    "8": "ACT",
}
ABS_OTHER_TERRITORIES = "9"

# The four Other Territories, each by a box well around it (south, west, north, east).
OTHER_TERRITORY_BOXES: dict[str, tuple[float, float, float, float]] = {
    "JBT": (-35.30, 150.50, -35.00, 150.85),
    "CX": (-10.65, 105.45, -10.35, 105.80),
    "CC": (-12.35, 96.70, -11.75, 97.00),
    "NF": (-29.20, 167.80, -28.90, 168.10),
}

# CAPAD's ``STATE`` → the app's code. "EXT" is the external territories, told apart by
# where the record lies.
CAPAD_STATES = frozenset({"NSW", "VIC", "QLD", "SA", "WA", "TAS", "NT", "ACT", "JBT"})
CAPAD_EXTERNAL = "EXT"

NAMES: dict[str, str] = {
    "ACT": "Australian Capital Territory", "NSW": "New South Wales",
    "NT": "Northern Territory", "QLD": "Queensland", "SA": "South Australia",
    "TAS": "Tasmania", "VIC": "Victoria", "WA": "Western Australia",
    "CX": "Christmas Island", "CC": "Cocos (Keeling) Islands",
    "JBT": "Jervis Bay Territory", "NF": "Norfolk Island",
}

# State → passport book (ADR 0014): New South Wales with the ACT and Jervis Bay; the
# island territories together.
PASSPORT_REGION_OF: dict[str, str] = {
    **dict.fromkeys(("NSW", "ACT", "JBT"), "newSouthWales"),
    "VIC": "victoria",
    "QLD": "queensland",
    "SA": "southAustralia",
    "WA": "westernAustralia",
    "TAS": "tasmania",
    "NT": "northernTerritory",
    **dict.fromkeys(("CX", "CC", "NF"), "externalTerritories"),
}
PASSPORT_REGIONS = frozenset(PASSPORT_REGION_OF.values())

# Each state's main zone, as ``Subdivision.mainTimeZoneID`` in the app names it: the
# fallback for a place whose centre the zone lookup does not answer as Australian.
MAIN_TIME_ZONES: dict[str, str] = {
    "NSW": "Australia/Sydney", "VIC": "Australia/Melbourne", "QLD": "Australia/Brisbane",
    "SA": "Australia/Adelaide", "WA": "Australia/Perth", "TAS": "Australia/Hobart",
    "NT": "Australia/Darwin", "ACT": "Australia/Sydney", "JBT": "Australia/Sydney",
    "CX": "Indian/Christmas", "CC": "Indian/Cocos", "NF": "Pacific/Norfolk",
}

# The IANA zones in Australia and its territories: a lookup that answers anything else (a
# sea's ``Etc/GMT-10``) is not one. Broken Hill keeps South Australia's time in New South
# Wales, the Whitsundays have Lindeman's (Brisbane's), and Eucla its own quarter hour.
AUSTRALIAN_ZONES = frozenset({
    "Australia/Sydney", "Australia/Melbourne", "Australia/Brisbane", "Australia/Lindeman",
    "Australia/Adelaide", "Australia/Broken_Hill", "Australia/Perth", "Australia/Eucla",
    "Australia/Hobart", "Australia/Currie", "Australia/Darwin", "Australia/Lord_Howe",
    "Australia/Canberra", "Indian/Christmas", "Indian/Cocos", "Pacific/Norfolk",
})


def subdivision(code: str) -> str:
    """``"NSW"`` → ``"AU-NSW"``."""
    return f"AU-{code}"


def other_territory(latitude: float, longitude: float) -> str | None:
    """Which of the Other Territories a point lies in, or None."""
    for code, (south, west, north, east) in OTHER_TERRITORY_BOXES.items():
        if south <= latitude <= north and west <= longitude <= east:
            return code
    return None


def abs_state(
    code: Any, latitude: float | None = None, longitude: float | None = None
) -> str | None:
    """The ABS's ``state_code_2021`` (``"1"``) → ``"NSW"``; Other Territories by place."""
    text = str(code or "").strip()
    if text in ABS_STATES:
        return ABS_STATES[text]
    if text == ABS_OTHER_TERRITORIES and latitude is not None and longitude is not None:
        return other_territory(latitude, longitude)
    return None


def capad_state(state: Any, latitude: float | None = None,
                longitude: float | None = None) -> str | None:
    """CAPAD's ``STATE`` → the app's code; "EXT" (the external territories) by place."""
    text = str(state or "").strip().upper()
    if text in CAPAD_STATES:
        return text
    if text == CAPAD_EXTERNAL and latitude is not None and longitude is not None:
        return other_territory(latitude, longitude)
    return None


def capad_state_of(subdivision_code: str) -> str:
    """``"AU-NF"`` → ``"EXT"``, ``"AU-JBT"`` → ``"JBT"``: what CAPAD calls the state."""
    code = subdivision_code.removeprefix("AU-")
    return CAPAD_EXTERNAL if code in ("CX", "CC", "NF") else code


def passport_region(code: str | None) -> str | None:
    return PASSPORT_REGION_OF.get(code or "")


def time_zone(found: str | None, codes: list[str]) -> str | None:
    """The zone a place keeps: the lookup's answer at its centre where that is an
    Australian zone (Mungo keeps Sydney's, a park beside Broken Hill Broken Hill's), else
    its first state's main zone. An island territory always keeps its own."""
    first = codes[0] if codes else None
    if first in ("CX", "CC", "NF"):
        return MAIN_TIME_ZONES[first]
    if found in AUSTRALIAN_ZONES:
        return "Australia/Sydney" if found == "Australia/Canberra" else found
    return MAIN_TIME_ZONES.get(first or "")


# MARK: - CAPAD

# The designations a national park's own records carry. Daintree's and Boodjamulla's
# handed-back parts are "National Park Aboriginal"; the Commonwealth's six are
# "National Park (Commonwealth)".
NATIONAL_PARK_TYPES = frozenset({
    "National Park", "National Park (Commonwealth)", "National Park Aboriginal",
})
SECOND_TIER_TYPE = "National Park"
"""The second tier is every other park CAPAD types exactly "National Park"."""

# CAPAD's ``AUTHORITY`` → the body that manages a state's national parks, as the app's
# ``managedBy`` names it. Each is the agency its state's national parks act gives them to
# (NPWS within NSW DCCEEW, QPWS within Queensland's department, the PWS within NRE
# Tasmania). Victoria's records name the department, which is kept as it is: most of its
# parks are Parks Victoria's, but not all (Port Campbell is the Great Ocean Road
# authority's), and CAPAD does not say which.
AUTHORITIES: dict[str, str] = {
    "NSW_DCCEEW": "NSW National Parks and Wildlife Service",
    "QLD_DES": "Queensland Parks and Wildlife Service",
    "WA_DBCA": "Department of Biodiversity, Conservation and Attractions (WA)",
    "NT_PWCNT": "Parks and Wildlife Commission of the Northern Territory",
    "SA_DEW": "Department for Environment and Water (SA)",
    "NRE_TAS": "Parks and Wildlife Service Tasmania",
    "ACT_EPSDD": "ACT Parks and Conservation Service",
    "VIC_DEECA": "Department of Energy, Environment and Climate Action (Victoria)",
    "DCCEEW": "Parks Australia",
}

PARKS_AUSTRALIA = "Parks Australia"


def agency(managing_body: str | None) -> str:
    """The app's ``Agency`` raw value for a park's managing body: Parks Australia's own,
    or a state's, whose name then travels as ``managedBy`` (ADR 0014)."""
    return "parksAustralia" if managing_body == PARKS_AUSTRALIA else "stateAgency"


_LIMITED_DEPTH = re.compile(r"\s*\(Limited Depth\)\s*$", re.IGNORECASE)
_UNNAMED = re.compile(r"^unnamed\b", re.IGNORECASE)


def display_name(name: str) -> str | None:
    """The park's name as the app shows it, CAPAD's ``NAME`` without the tenure note
    Queensland adds ("Cudmore (Limited Depth)" → "Cudmore"); None for a record CAPAD
    names only by number ("Unnamed WA17519")."""
    text = re.sub(r"\s+", " ", (name or "").replace("\xa0", " ")).strip()
    text = _LIMITED_DEPTH.sub("", text).strip()
    if not text or _UNNAMED.match(text):
        return None
    return text


def identifier_names(name: str) -> list[str]:
    """The names an identifier may be made from, best first: the whole name, then each
    part of a dual one ("Tjoritja / West MacDonnell", "Bandilngan (Windjana Gorge)")."""
    parts = [name]
    parts.extend(part.strip() for part in re.split(r"\s*/\s*|\s*\(|\)", name) if part.strip())
    return list(dict.fromkeys(parts))


AREA_AGREEMENT = 0.25
"""How far a park's gazetted area may differ from its mapped one and still be believed."""


def _positive(value: Any) -> float | None:
    try:
        number = float(value) if value is not None else None
    except (TypeError, ValueError):
        return None
    return number if number and number > 0 else None


def area_hectares(records: list[dict[str, Any]]) -> tuple[float | None, str | None]:
    """A park's area in hectares and what it is: ``"gazetted"`` (CAPAD's ``GAZ_AREA``)
    where every record gives one and their total agrees with the mapped area to within
    :data:`AREA_AGREEMENT`, else ``"mapped"`` (``GIS_AREA``, the area of CAPAD's own
    boundary). The Northern Territory repeats a park's whole gazetted area on each of its
    parcels, so the same figure on every record is counted once. Tasmania and the ACT
    record no gazetted area; South Australia's do not always describe the parcel."""
    mapped_values = [_positive(record.get("GIS_AREA")) for record in records]
    mapped = sum(value for value in mapped_values if value) or None
    gazetted_values = [_positive(record.get("GAZ_AREA")) for record in records]
    gazetted: float | None = None
    if gazetted_values and all(value is not None for value in gazetted_values):
        values = [value for value in gazetted_values if value is not None]
        gazetted = values[0] if len(values) > 1 and len(set(values)) == 1 else sum(values)
    if gazetted and mapped and abs(gazetted - mapped) <= AREA_AGREEMENT * mapped:
        return round(gazetted, 1), "gazetted"
    if mapped:
        return round(mapped, 1), "mapped"
    return None, None


# MARK: - Queensland's tracks

QPWS_TRACKS_URL = (
    "https://www.data.qld.gov.au/dataset/queensland-parks-and-wildlife-service-access"
)
GRADE_PUBLISHER = "Queensland Parks and Wildlife Service"
GRADE_SYSTEM = "australianWalkingTrackGrade"

# The Australian Walking Track Grading System's five grades (built on the track classes of
# AS 2156.1), and the band of the app's five each reads as. The bands are Unigrids'
# reading, not QPWS's.
BANDS: dict[str, str] = {
    "1": "easy",
    "2": "easy",
    "3": "moderate",
    "4": "strenuous",
    "5": "veryStrenuous",
}
_TRACK_CLASS = re.compile(r"^\s*track class\s+([1-5])\s+to\s+AS\s*2156\.1\s*$", re.IGNORECASE)

# ``class`` values that a walker uses as a track.
WALKED_CLASSES = frozenset({"walking track", "boardwalk", "stairs or steps or ladder",
                            "pedestrian bridge"})


def track_grade(value: Any) -> str | None:
    """``"Track class 3 to AS 2156.1"`` → ``"3"``; "Unclassified" or anything else →
    None."""
    match = _TRACK_CLASS.match(str(value or ""))
    return match.group(1) if match else None


def band(grade: str | None) -> str | None:
    """The app's difficulty band for a grade (``TrailDifficulty``'s raw value)."""
    return BANDS.get(grade or "")


def published_grade(grade: str) -> dict[str, Any]:
    """A grade in the shape the app's ``TrailGrade`` takes."""
    return {
        "system": GRADE_SYSTEM,
        "grade": grade,
        "publisher": GRADE_PUBLISHER,
        "sourceURL": QPWS_TRACKS_URL,
    }


def is_open_walking_track(properties: dict[str, Any]) -> bool:
    """A QPWS record a visitor walks: open, and a track or a structure on one, or any
    line QPWS gives a walking-track class (the Border Track is a "minimally formed" fire
    trail of class 4)."""
    if (properties.get("status") or "").strip().lower() != "open":
        return False
    walked = (properties.get("class") or "").strip().lower() in WALKED_CLASSES
    return walked or track_grade(properties.get("ped")) is not None


# Lamington's records open with the section of the park they are in, Binna Burra or
# Green Mountains ("BB - Caves circuit", "GM - Box Forest Circuit"): QPWS's filing, not
# the track's name.
_SECTION = re.compile(r"^(?:BB|GM)\s*-?\s+(?=\S)|^(?:BB|GM)-\s*")


def track_name(name: Any) -> str:
    """A track's name as QPWS records it, without Lamington's section codes."""
    text = re.sub(r"\s+", " ", str(name or "").replace("\xa0", " ")).strip()
    return _SECTION.sub("", text).strip()


# MARK: - Facilities from OpenStreetMap

_NOT_PUBLIC = re.compile(r"\(closed\)|\bprivate\b|\branger'?s?\b|\bstaff\b", re.IGNORECASE)


def facility_kind(tags: dict[str, str]) -> str | None:
    """``visitorCentre``, ``campground`` or ``hut`` for an OpenStreetMap element, else
    None. A campsite only for groups, caravans or backpackers stays a campground."""
    tourism = tags.get("tourism")
    if tourism in ("alpine_hut", "wilderness_hut"):
        return "hut"
    if tourism == "camp_site":
        return "campground"
    if tourism == "information" and tags.get("information") == "office":
        return "visitorCentre"
    return None


_VISITOR_CENTRE = re.compile(
    r"\b(?:visitors?'?|information|discovery|interpretive|cultural|heritage)\b.*\bcent(?:re|er)\b"
    r"|\binformation (?:office|bay)\b|\bvisitor (?:hub|information)\b",
    re.IGNORECASE,
)
_ANOTHER_PLACE = re.compile(
    r"\b(?:dam|nature reserve|botanic|kiosk|cruises?|tours?|welcome)\b", re.IGNORECASE
)


def is_visitor_centre_name(name: str) -> bool:
    """Whether an information office's name says it is a visitor centre ("Bowali Visitor
    Centre", "Mungo Visitor Centre"), not a tour desk, a kiosk or another reserve's."""
    return bool(_VISITOR_CENTRE.search(name)) and not _ANOTHER_PLACE.search(name)


def is_public(tags: dict[str, str]) -> bool:
    name = tags.get("name") or ""
    return tags.get("access") not in ("private", "no") and not _NOT_PUBLIC.search(name)


def facility_summary(tags: dict[str, str]) -> str | None:
    """"Wilderness hut · Parks and Wildlife Service Tasmania", "Campground · fee", from
    the element's own tags."""
    kind = {
        "alpine_hut": "Alpine hut", "wilderness_hut": "Wilderness hut",
        "camp_site": "Campground", "information": "Visitor centre",
    }.get(tags.get("tourism") or "")
    parts = [kind] if kind else []
    operator = (tags.get("operator") or "").strip()
    if operator and not operator.startswith(("http://", "https://", "www.")):
        parts.append(operator)
    if tags.get("tourism") == "camp_site" and tags.get("fee") in ("yes", "no"):
        parts.append("fee" if tags["fee"] == "yes" else "no fee")
    return " · ".join(parts) or None


# MARK: - Rail

# The passenger networks a visitor travels on, as OpenStreetMap's ``network`` names them:
# the states' regional trains and the cities' networks.
RAIL_NETWORKS = frozenset({
    "NSW TrainLink", "Sydney Trains", "Sydney Metro", "PTV - Metropolitan Trains",
    "PTV - Regional Trains", "V/Line", "Translink", "Translink Nightlink",
    "Queensland Rail Travel", "Transperth", "Transwa", "Adelaide Metro",
})
RAIL_OPERATORS = frozenset({
    "NSW TrainLink", "NSW Trains", "Sydney Trains", "V/Line", "Metro Trains Melbourne",
    "Queensland Rail", "Transperth", "Transwa", "Journey Beyond Rail Expeditions",
    "Journey Beyond", "Great Southern Railway",
})
# Journey Beyond's long-distance trains and Transwa's, some mapped with neither tag.
_NAMED_TRAINS = re.compile(
    r"\b(?:the ghan|indian ?pacific|the overland|prospector|australind|avonlink"
    r"|merredinlink)\b",
    re.IGNORECASE,
)
_GONE = frozenset({"abandoned", "disused", "razed", "proposed", "construction"})


def is_passenger_service(tags: dict[str, str]) -> bool:
    """A train a visitor can take today: run by one of the networks or operators above,
    or one of the named long-distance trains; never a closed, freight or museum line."""
    if tags.get("railway") in _GONE or tags.get("service") in ("industrial", "freight"):
        return False
    return (
        tags.get("network") in RAIL_NETWORKS
        or tags.get("operator") in RAIL_OPERATORS
        or bool(_NAMED_TRAINS.search(tags.get("name") or ""))
    )


_LINE_PREFIX = re.compile(r"^(?P<line>[^:]+?):\s")
_PLATFORM = re.compile(r"(?:\s+(?:Railway\s+)?Station)?(?:,\s*Platform\s+\w+)?\s*$",
                       re.IGNORECASE)


def line_tags(tags: dict[str, str]) -> dict[str, str]:
    """A route's tags as the line it is one service of: a number without Melbourne's
    through-running destination ("CBE=>WFY" → "CBE"); a train's name where the number
    field holds one ("Spirit of Queensland"); the line or train a service's name opens
    with ("Airport Line: Perth–High Wycombe" → "Airport Line"). Its ends are places, not
    platforms."""
    tags = dict(tags)
    ref = (tags.get("ref") or "").strip()
    name = (tags.get("name") or "").strip()
    code = ref.split("=>")[0].split("=")[0].strip()
    if code and (any(character.isdigit() for character in code)
                 or (code.isupper() and len(code) <= 6)):
        tags["ref"] = code
    elif ref:
        del tags["ref"]
        tags["name"] = ref
    elif match := _LINE_PREFIX.match(name):
        tags["name"] = match.group("line").strip()
    for end in ("from", "to"):
        if tags.get(end):
            tags[end] = terminus(tags[end])
    return tags


def terminus(name: str | None) -> str:
    """"Casino Station, Platform 1" → "Casino": a route's end as a place."""
    return _PLATFORM.sub("", (name or "").strip()).strip()


# MARK: - Official pages and documents

# The agencies' park pages, as a guide's sources give them first.
AGENCY_PAGES = (
    "https://parksaustralia.gov.au/",
    "https://www.nationalparks.nsw.gov.au/visit-a-park/parks/",
    "https://www.parks.act.gov.au/",
    "https://www.parks.vic.gov.au/places-to-see/parks/",
    "https://www.greatoceanroadauthority.vic.gov.au/",
    "https://parks.qld.gov.au/parks/",
    "https://www.parks.sa.gov.au/parks/",
    "https://exploreparks.dbca.wa.gov.au/park/",
    "https://parks.tas.gov.au/",
    "https://nt.gov.au/parks/find-a-park/",
)


def official_page(sources: Any) -> str | None:
    """The park's own page on its agency's site: the first of a guide's sources there."""
    for source in sources or []:
        url = (source or {}).get("url") if isinstance(source, dict) else None
        if isinstance(url, str) and url.startswith(AGENCY_PAGES) and not url.endswith(".pdf"):
            return url
    return None


_NOT_THE_PARKS = re.compile(
    r"\b(?:polic(?:y|ies)|disclosures?|privacy|terms of use|accessibility|annual report)\b",
    re.IGNORECASE,
)


def document_title(title: str) -> str:
    """A link's text without the soft hyphens a page breaks long words with."""
    return re.sub(r"\s+", " ", title.replace("\xad", "")).strip()


def is_the_parks_document(title: str) -> bool:
    """Whether a PDF a park page links is about the park, not the agency's own
    governance (a footer's "Public Interest Disclosure Policy")."""
    return not _NOT_THE_PARKS.search(title)


def document_kind(title: str, url: str) -> str:
    text = f"{title} {url.rsplit('/', 1)[-1]}".lower()
    if "map" in text:
        return "map"
    if any(word in text for word in ("guide", "brochure", "visitor", "park notes", "factsheet",
                                     "fact sheet")):
        return "brochure"
    return "other"
