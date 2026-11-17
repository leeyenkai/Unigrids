"""Norway's rules, kept apart from any download so they can be tested on their own: which
county and region a place belongs to, which language an official name is in, how a
designation comes off a name, and which reserves are large enough to carry.

Everything here reads Miljødirektoratet's Naturvernområder fields as the service
publishes them (``kommune`` as ``"Lom (3434),Vågå (3435)"``, ``offisieltNavn`` as
``"Reisa nasjonalpark/Ráissa álbmotmeahcci"``) and never invents a value it does not find.
"""

from __future__ import annotations

import datetime as dt
import re
from typing import Any

from ... import outline

# MARK: - Counties and regions

# County number → name, for the fifteen counties from 1 January 2024 and Svalbard (which
# lies outside the county system but keeps ISO 3166-2 NO-21). ``Subdivision`` in the app
# carries the same list; a code it does not know is dropped there, never shown.
COUNTIES: dict[str, str] = {
    "03": "Oslo",
    "11": "Rogaland",
    "15": "Møre og Romsdal",
    "18": "Nordland",
    "21": "Svalbard",
    "31": "Østfold",
    "32": "Akershus",
    "33": "Buskerud",
    "34": "Innlandet",
    "39": "Vestfold",
    "40": "Telemark",
    "42": "Agder",
    "46": "Vestland",
    "50": "Trøndelag",
    "55": "Troms",
    "56": "Finnmark",
}

# County → passport region. The regions are Norway's own landsdeler, with Svalbard apart.
REGION_OF_COUNTY: dict[str, str] = {
    "18": "northernNorway",
    "55": "northernNorway",
    "56": "northernNorway",
    "50": "trondelag",
    "11": "westernNorway",
    "15": "westernNorway",
    "46": "westernNorway",
    "03": "easternNorway",
    "31": "easternNorway",
    "32": "easternNorway",
    "33": "easternNorway",
    "34": "easternNorway",
    "39": "easternNorway",
    "40": "easternNorway",
    "42": "southernNorway",
    "21": "svalbard",
}

SVALBARD = "21"

_MUNICIPALITY = re.compile(r"\((\d{4})\)")


def municipality_numbers(kommune: str | None) -> list[str]:
    """``"Lom (3434),Vågå (3435)"`` → ``["3434", "3435"]``, in the order given.

    Municipality names carry commas and parentheses of their own ("Herøy (Nordland)
    (1818)"), so the four-digit numbers are what is read, never the names.
    """
    numbers: list[str] = []
    for number in _MUNICIPALITY.findall(kommune or ""):
        if number not in numbers:
            numbers.append(number)
    return numbers


def county_codes(kommune: str | None) -> list[str]:
    """The counties a place's municipalities lie in, as known county numbers, in the
    order the municipalities are listed. A municipality number's first two digits are its
    county's; one outside the list (Jan Mayen, 22) is not a county and is left out."""
    codes: list[str] = []
    for number in municipality_numbers(kommune):
        county = number[:2]
        if county in COUNTIES and county not in codes:
            codes.append(county)
    return codes


def subdivision(county: str) -> str:
    """``"34"`` → ``"NO-34"``."""
    return f"NO-{county}"


def region_of(county: str | None) -> str | None:
    return REGION_OF_COUNTY.get(county or "")


def ordered_counties(listed: list[str], shares: dict[str, int]) -> list[str]:
    """The listed counties, largest share of the place first; a county the outline
    sampling never landed in (a sliver, or water) keeps its listed place after them."""
    return sorted(listed, key=lambda code: (-shares.get(code, 0), listed.index(code)))


def main_county(listed: list[str], shares: dict[str, int]) -> str | None:
    """The county holding most of the place's area. Shares come from sampling the
    outline against the county polygons; the listed municipalities are the fallback when
    no sample landed in any county (a place at sea, or on Svalbard, which the county
    polygons do not cover)."""
    if SVALBARD in listed:
        return SVALBARD
    if shares:
        return max(shares, key=lambda code: (shares[code], -_index(listed, code)))
    return listed[0] if listed else None


def _index(listed: list[str], code: str) -> int:
    return listed.index(code) if code in listed else len(listed)


class Counties:
    """Which county a point lies in, by point in polygon against Kartverket's county
    outlines (fifteen counties; Svalbard is not among them).

    The outlines are generalised to about 500 m first: they only ever decide which of a
    place's own counties holds more of it, and at full detail the coastal counties' tens
    of thousands of island rings make every test slow."""

    TOLERANCE = 0.005

    def __init__(
        self, counties: dict[str, list[outline.Polygon]], *, tolerance: float = TOLERANCE
    ) -> None:
        self._counties: dict[str, tuple[list[outline.Polygon], tuple[float, ...]]] = {}
        for code, polygons in sorted(counties.items()):
            coarse = outline.generalise(polygons, tolerance)
            if coarse and (box := outline.bbox(coarse)):
                self._counties[code] = (coarse, box)

    @property
    def codes(self) -> list[str]:
        return list(self._counties)

    def at(
        self, latitude: float, longitude: float, among: list[str] | None = None
    ) -> str | None:
        for code in among if among is not None else self._counties:
            if code not in self._counties:
                continue
            polygons, (south, west, north, east) = self._counties[code]
            if south <= latitude <= north and west <= longitude <= east and outline.contains(
                polygons, longitude, latitude
            ):
                return code
        return None

    def shares(
        self, polygons: list[outline.Polygon], among: list[str] | None = None
    ) -> dict[str, int]:
        """How many of a grid of points inside the place fall in each county: shares by
        area. ``among`` limits the test to the counties the place's own municipalities
        name; a place in one county needs no sampling at all. A place too small or
        scattered for the grid is sampled along its outline."""
        if among is not None and len(among) == 1:
            return {among[0]: 1}
        box = outline.bbox(polygons)
        samples: list[tuple[float, float]] = []
        if box is not None:
            south, west, north, east = box
            steps = 16
            for row in range(steps):
                latitude = south + (north - south) * (row + 0.5) / steps
                for column in range(steps):
                    longitude = west + (east - west) * (column + 0.5) / steps
                    if outline.contains(polygons, longitude, latitude):
                        samples.append((latitude, longitude))
        if len(samples) < 20:
            vertices = [point for polygon in polygons for point in polygon[0]]
            step = max(1, len(vertices) // 120)
            samples.extend((lat, lon) for lon, lat in vertices[::step])
        counts: dict[str, int] = {}
        for latitude, longitude in samples:
            if code := self.at(latitude, longitude, among or None):
                counts[code] = counts.get(code, 0) + 1
        return counts


# MARK: - Names


# The designations an official name ends in, in Norwegian, Sámi and Kven, with the
# protections a landscape area adds ("… landskapsvernområde med dyrelivsfredning"). The
# service's own spelling slips ("naturresevat", "natureservat") are among them.
_DESIGNATION = re.compile(
    r"\s+(?:"
    r"nasjonalpark|landskapsvernområder?|natur\w*re\w*vat|fuglereservat|\w*fredningsområde"
    r"|álbmotmeahcci|nasjonalpárkka|suoddjimpárkka|nasjonaalpaarhke|vaarjelimmiedajve"
    r"|suodjemeahcci|luondumeahcci|eatnemedajve|eatnemedavje|eatnemereservaate"
    r"|kansalistarhaan|kansalistaras|suojeluala"
    r")\b.*$",
    re.IGNORECASE,
)


def strip_designation(name: str) -> str:
    """``"Dividalen landskapsvernområde"`` → ``"Dividalen"``.

    Each form of a name separated by a slash loses its own designation, so
    ``"Skardmodalen naturreservat/Skaalma eatnemedajve"`` reads ``"Skardmodalen/Skaalma"``,
    as the service's own short name does. A name without one is returned as it is,
    spacing and all ("Mariafjellet - Skardbekken / Tjaetsiegaske").
    """
    if not _DESIGNATION.search(name):
        return _squash(name)
    parts = [
        _DESIGNATION.sub("", _squash(part))
        for part in re.split(r"\s*/\s*", name.strip())
    ]
    stripped = "/".join(part for part in parts if part)
    return stripped or _squash(name)


def _squash(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


# Which language each form of a national park's official name is in, read off the word
# for "national park" it carries. South Sámi names that take the Norwegian word
# ("Låarte-Skæhkere nasjonalpark", "Lijre nasjonalpark") are known by name.
_SOUTH_SAMI_NAMES = ("låarte-skæhkere", "lijre")
_LANGUAGE_WORDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("se", ("álbmotmeahcci",)),
    ("smj", ("nasjonalpárkka", "suoddjimpárkka")),
    ("sma", ("nasjonaalpaarhke", "vaarjelimmiedajve")),
    ("fkv", ("kansalistarhaan", "kansalistaras")),
    ("nb", ("nasjonalpark",)),
)


def name_language(form: str) -> str | None:
    """The BCP 47 tag of one form of an official name: ``nb``, ``se`` (North Sámi),
    ``smj`` (Lule Sámi), ``sma`` (South Sámi) or ``fkv`` (Kven); ``None`` if the form
    carries no word that says."""
    lowered = form.lower()
    if lowered.startswith(_SOUTH_SAMI_NAMES):
        return "sma"
    for language, words in _LANGUAGE_WORDS:
        if any(word in lowered for word in words):
            return language
    return None


def local_names(official: str | None) -> tuple[list[dict[str, str]], list[str]]:
    """Every form of a national park's official name, tagged with its language, and the
    forms no rule could tag (for the build to report).

    ``offisieltNavn`` packs the forms into one string with slashes and irregular spacing.
    Where forms share one designation — ``"Lierne/Lijre nasjonalpark"`` — the bare form
    takes the designation of the form after it: Lierne nasjonalpark, Lijre nasjonalpark.
    """
    forms = [_squash(part) for part in (official or "").split("/") if _squash(part)]
    completed: list[str] = []
    for index, form in enumerate(forms):
        if not _DESIGNATION.search(form):
            following = next(
                (later for later in forms[index + 1:] if _DESIGNATION.search(later)), None
            )
            if following and (match := _DESIGNATION.search(following)):
                form = f"{form}{match.group(0)}"
        completed.append(form)
    names: list[dict[str, str]] = []
    unknown: list[str] = []
    for form in completed:
        language = name_language(form)
        if language is None:
            unknown.append(form)
            continue
        entry = {"language": language, "text": form}
        if entry not in names:
            names.append(entry)
    return names, unknown


# MARK: - Second tier


# The smallest nature reserve the map carries, in square metres (10 km²). Norway has
# 2,752 reserves; the threshold keeps the ones a visitor plans a day around.
RESERVE_MINIMUM_M2 = 10_000_000
# The fetch keeps reserves from half that, so the threshold can be reported and moved.
RESERVE_FETCH_MINIMUM_M2 = 5_000_000
REPORT_THRESHOLDS_KM2 = (5, 10, 25)

NATIONAL_PARK_FORMS = ("Nasjonalpark", "NasjonalparkSvalbard")


def tier_of(verneform: str | None) -> str | None:
    """``np``, ``lvo`` or ``nr`` for a Naturvernområder ``verneform``, else ``None``.

    Landscape areas come in combined forms ("LandskapsvernomraadeDyrelivsfredning") and
    reserves in Svalbard's and Jan Mayen's ("NaturreservatSvalbard"); all count."""
    form = verneform or ""
    if form in NATIONAL_PARK_FORMS:
        return "np"
    if form.startswith("Landskapsvernomraade"):
        return "lvo"
    if form.startswith("Naturreservat"):
        return "nr"
    return None


def area_m2(properties: dict[str, Any]) -> float:
    """The official geometry's area as the service measures it, in square metres."""
    value = properties.get("SHAPE.STArea()")
    try:
        return float(value) if value is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def carries_reserve(properties: dict[str, Any]) -> bool:
    """Whether a nature reserve is large enough for the map: 10 km² or more."""
    return area_m2(properties) >= RESERVE_MINIMUM_M2


def threshold_counts(areas_m2: list[float]) -> dict[int, int]:
    """How many reserves reach each reported threshold, in km²."""
    return {
        threshold: sum(1 for area in areas_m2 if area >= threshold * 1_000_000)
        for threshold in REPORT_THRESHOLDS_KM2
    }


def year_of(milliseconds: Any) -> int | None:
    """The year of an ArcGIS date (milliseconds since 1970, negative before it)."""
    if milliseconds is None:
        return None
    try:
        moment = dt.datetime(1970, 1, 1, tzinfo=dt.UTC) + dt.timedelta(
            milliseconds=float(milliseconds)
        )
    except (TypeError, ValueError, OverflowError):
        return None
    # A date kept as midnight in Norway is the evening before in UTC; two hours forward
    # lands on the right day whichever way the service stored it.
    return (moment + dt.timedelta(hours=2)).year


def established_year(properties: dict[str, Any]) -> int | None:
    """When the area was first protected (``foerstegangVernet``), or None.

    ``vernedato`` is the date of the current regulation, which for an area re-regulated
    since is years after it was first protected: Utladalen, protected in 1980 with
    Jotunheimen, carries 2014. Shown as "Protected", it would be a plausible wrong
    figure, so where the service leaves the first date empty the year stays absent."""
    return year_of(properties.get("foerstegangVernet"))


# MARK: - Huts


_DNT = re.compile(r"\bDNT\b|turistforening", re.IGNORECASE)


def hut_summary(tags: dict[str, str]) -> str | None:
    """A hut's one line, from who runs it as OpenStreetMap records: "DNT cabin" when the
    operator, brand or network says the Norwegian Trekking Association; otherwise who
    runs it; otherwise nothing, rather than a guess at its service level."""
    operator = _squash(tags.get("operator") or "")
    if any(_DNT.search(tags.get(key) or "") for key in ("operator", "brand", "network")):
        return "DNT cabin"
    if operator:
        return f"Run by {operator}"
    return None
