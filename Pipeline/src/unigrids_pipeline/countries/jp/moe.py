"""Reading what the Ministry of the Environment publishes: the quasi-national park list,
the regional office page, the visitor statistics workbook and the English brochure page.

Each is a page or file made for people, not an API, so each parser is small, pinned by a
test on a cut-down copy, and loud when the page changes shape: a list that comes back
short fails the build instead of shipping fifty parks as fifty-eight.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import xlsx

QUASI_LIST_URL = "https://www.env.go.jp/nature/nationalparks/about/quasi-national-park/"
OFFICE_URL = "https://www.env.go.jp/park/office.html"
VISITORS_URL = "https://www.env.go.jp/park/doc/data/natural/naturalpark_04.xlsx"
VISITOR_CENTRES_URL = "https://www.env.go.jp/park/doc/data/natural/naturalpark_08.xlsx"
STATISTICS_PAGE = "https://www.env.go.jp/park/doc/data.html"
BROCHURE_URL = "https://www.japan.travel/national-parks/plan-your-visit/map-brochure-download/"
PARK_PAGE = "https://www.japan.travel/national-parks/parks/{slug}/"

QUASI_PARK_COUNT = 58
NATIONAL_PARK_COUNT = 35

# The prefectures by their Japanese names, in ISO 3166-2:JP order: 北海道 is JP-01.
PREFECTURES = (
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県",
    "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県",
    "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
    "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県",
    "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県",
    "鹿児島県", "沖縄県",
)
PREFECTURE_CODES = {name: f"JP-{index:02d}" for index, name in enumerate(PREFECTURES, start=1)}

# The same prefectures in English, in the same order: what a quasi-national park's
# managing body is called. Hokkaido and Tokyo are not 県 and are named as they are.
PREFECTURE_NAMES = (
    "Hokkaido", "Aomori", "Iwate", "Miyagi", "Akita", "Yamagata", "Fukushima", "Ibaraki",
    "Tochigi", "Gunma", "Saitama", "Chiba", "Tokyo", "Kanagawa", "Niigata", "Toyama",
    "Ishikawa", "Fukui", "Yamanashi", "Nagano", "Gifu", "Shizuoka", "Aichi", "Mie", "Shiga",
    "Kyoto", "Osaka", "Hyogo", "Nara", "Wakayama", "Tottori", "Shimane", "Okayama",
    "Hiroshima", "Yamaguchi", "Tokushima", "Kagawa", "Ehime", "Kochi", "Fukuoka", "Saga",
    "Nagasaki", "Kumamoto", "Oita", "Miyazaki", "Kagoshima", "Okinawa",
)


class PageChangedError(ValueError):
    """A Ministry page no longer reads the way its parser expects."""


def prefecture_code(name: str) -> str | None:
    """``長野県`` or ``長野`` → ``JP-20``."""
    cleaned = re.sub(r"\s+", "", name)
    if cleaned in PREFECTURE_CODES:
        return PREFECTURE_CODES[cleaned]
    for full, code in PREFECTURE_CODES.items():
        # The statistics write 長野 for 長野県 and 京都 for 京都府; 北海道 is whole.
        short = full[:-1] if full[-1] in "都府県" else full
        if cleaned == short:
            return code
    return None


def managing_body(codes: list[str]) -> str | None:
    """The prefectures that run a quasi-national park, as one phrase:
    ``Nagano Prefecture``, ``Nagano and Gifu prefectures``, ``Hokkaido``,
    ``Tokyo Metropolitan Government``."""
    names = [PREFECTURE_NAMES[int(code[3:]) - 1] for code in codes]
    if not names:
        return None
    if names == ["Hokkaido"]:
        return "Hokkaido"
    if names == ["Tokyo"]:
        return "Tokyo Metropolitan Government"
    if len(names) == 1:
        return f"{names[0]} Prefecture"
    listed = ", ".join(names[:-1]) + f" and {names[-1]}"
    return f"{listed} prefectures"


# MARK: - Quasi-national parks


@dataclass(frozen=True)
class QuasiPark:
    """One entry of the Ministry's list."""

    name: str
    """The official name, ``御嶽山国定公園``."""
    prefectures: list[str]
    """ISO codes of the prefectures the list tags it with, in the list's order."""
    feature: str | None
    """The Ministry's one-line description of its landscape, in Japanese."""
    url: str | None
    """The managing prefecture's page about it, where the list links one."""


def quasi_parks(page: str, *, expected: int = QUASI_PARK_COUNT) -> list[QuasiPark]:
    """The quasi-national parks on the Ministry's list page, which must number
    ``expected``."""
    items = re.split(r'<li class="p-quasiList__item[\s"]', page)[1:]
    parks: list[QuasiPark] = []
    for item in items:
        title = re.search(r'class="p-quasiList__item__title[^"]*"[^>]*>(.*?)</div>', item, re.S)
        if not title:
            continue
        name = _text(title.group(1))
        tags = [_text(tag) for tag in re.findall(r'c-tagIconList__tag">(.*?)</li>', item, re.S)]
        codes = [code for tag in tags if (code := prefecture_code(tag))]
        detail = re.search(r'class="p-quasiList__item__detail"[^>]*>(.*?)</div>', item, re.S)
        link = re.search(r'p-quasiList__item__button.*?href="([^"]+)"', item, re.S)
        parks.append(QuasiPark(
            name=name,
            prefectures=codes,
            feature=_text(detail.group(1)) if detail else None,
            url=html.unescape(link.group(1)) if link else None,
        ))
    if len(parks) != expected or not all(park.name.endswith("国定公園") for park in parks):
        raise PageChangedError(
            f"the quasi-national park list read as {len(parks)} parks, not {expected}"
        )
    return parks


def _text(fragment: str) -> str:
    fragment = re.sub(r"<rt>.*?</rt>", "", fragment, flags=re.S)
    fragment = re.sub(r"<[^>]+>", "", fragment)
    return re.sub(r"\s+", "", html.unescape(fragment))


# MARK: - Regional offices


# MOE's seven 地区 on the office page, and the region each is in Unigrids' passport.
DISTRICT_REGIONS = {
    "hokkaido": "hokkaido",
    "tohoku": "tohoku",
    "kanto": "kanto",
    "chubu": "chubu",
    "kinki": "kinki",
    "chugoku": "chugokuShikoku",
    "kyushu": "kyushu",
}
# The office whose parks Unigrids files in their own region, not in 九州's.
OKINAWA_AMAMI_OFFICE = "沖縄奄美自然環境事務所"


@dataclass
class ParkOffices:
    """Where the office page files one national park."""

    regions: list[str] = field(default_factory=list)
    """Every passport region the page puts a row of the park in, in page order."""
    offices: list[str] = field(default_factory=list)
    """The regional bureaus and offices named for it (地方環境局等)."""


def park_offices(
    page: str, *, expected: int = NATIONAL_PARK_COUNT
) -> dict[str, ParkOffices]:
    """Short park name (``知床``) → the regions and offices the page lists it under."""
    result: dict[str, ParkOffices] = {}
    sections = re.split(r'<h2[^>]*id="([^"]+)"', page)
    for district, body in zip(sections[1::2], sections[2::2], strict=True):
        region = DISTRICT_REGIONS.get(district.lower())
        if region is None:
            continue
        current: str | None = None
        for row in re.findall(r"<tr>(.*?)</tr>", body, re.S):
            name_cell = re.search(r'class="c-table-3_td1"[^>]*>(.*?)</td>', row, re.S)
            if name_cell:
                current = _text(name_cell.group(1))
            office_cell = re.search(r'class="c-table-3_td3"[^>]*>(.*?)(?:<br|</td>)', row, re.S)
            if current is None:
                continue
            entry = result.setdefault(current, ParkOffices())
            office = _text(office_cell.group(1)) if office_cell else ""
            row_region = "okinawaAmami" if office == OKINAWA_AMAMI_OFFICE else region
            if row_region not in entry.regions:
                entry.regions.append(row_region)
            if office and office not in entry.offices:
                entry.offices.append(office)
    if len(result) != expected:
        raise PageChangedError(f"the office page read as {len(result)} parks, not {expected}")
    return result


# MARK: - Visitor statistics


# Era → the Gregorian year before its first year (令和元年 is 2019).
_ERAS = (("令和", 2018), ("平成", 1988), ("昭和", 1925))


@dataclass(frozen=True)
class AnnualVisitors:
    year: int
    visitors: int


def park_visitors(
    workbook: Path | bytes, *, expected: int = NATIONAL_PARK_COUNT
) -> dict[str, AnnualVisitors]:
    """Short park name → its visitors in the table's latest year.

    The table (表Ⅱ-1, 国立公園利用者数) is a print layout: five blocks of years side by
    side, each with a park-number column and a name column, and two rows per park — the
    first numbered and named, carrying the change on the year before in per cent; the
    second carrying the visitors in units of ten thousand (万人). A long name wraps onto
    the second row (``利尻礼文`` / ``サロベツ``). Only the block holding the latest year is
    read.
    """
    grid = xlsx.read_sheet(workbook)
    header_row, name_column, years = _latest_block(grid)
    number_column = name_column - 1
    latest = max(years)
    year_column = years[latest]
    result: dict[str, AnnualVisitors] = {}
    for row in sorted(grid):
        if row <= header_row:
            continue
        cells = grid[row]
        number = cells.get(number_column)
        if not isinstance(number, float) or number != int(number):
            continue
        name = park_name(str(cells.get(name_column) or ""))
        following = grid.get(row + 1, {})
        continuation = following.get(name_column)
        if isinstance(continuation, str):
            name += park_name(continuation)
        value = following.get(year_column)
        if not name or not isinstance(value, float):
            continue
        result[name] = AnnualVisitors(year=latest, visitors=round(value * 10_000))
    if len(result) < expected:
        raise PageChangedError(
            f"the visitor table read as {len(result)} parks, not {expected}"
        )
    return result


def park_name(text: str) -> str:
    """A park's name as the statistics write it, without footnote marks, line breaks or
    a former name in brackets: ``※日高山脈襟裳\\n　十勝`` → ``日高山脈襟裳十勝``."""
    text = re.sub(r"[（(][^）)]*[）)]", "", text)
    return re.sub(r"[\s※*＊]", "", text)


def _latest_block(grid: xlsx.Grid) -> tuple[int, int, dict[int, int]]:
    """The header row, the name column of the block with the latest years, and that
    block's year → column."""
    for row in sorted(grid):
        labels = [column for column, value in grid[row].items() if _is_year_label(value)]
        if not labels:
            continue
        era_base = 0
        years: dict[int, int] = {}
        owner: dict[int, int] = {}
        starts = sorted(labels)
        for column in sorted(grid[row]):
            if column in starts:
                continue
            value = grid[row][column]
            year, era_base = _year(value, era_base)
            if year is not None:
                years[year] = column
                owner[year] = max(start for start in starts if start < column)
        if not years:
            continue
        latest = max(years)
        block = owner[latest]
        return row, block, {
            year: column for year, column in years.items() if owner[year] == block
        }
    raise PageChangedError("no row of years in the visitor table")


def _is_year_label(value: Any) -> bool:
    return isinstance(value, str) and value.strip() == "年次"


def _year(value: Any, era_base: int) -> tuple[int | None, int]:
    """A header cell as a Gregorian year, given the era the row is in so far:
    ``昭和46年`` → 1971; ``47`` → 1972; ``平成元`` → 1989; ``31\\n/令和元`` → 2019."""
    if isinstance(value, float):
        return (era_base + int(value), era_base) if era_base else (None, era_base)
    if not isinstance(value, str):
        return None, era_base
    text = re.sub(r"\s", "", value)
    for era, base in _ERAS:
        if era in text:
            after = text.split(era, 1)[1]
            number = 1 if after.startswith("元") else int(re.match(r"\d*", after).group() or 0)
            return (base + number if number else None), base
    if re.fullmatch(r"\d+", text) and era_base:
        return era_base + int(text), era_base
    return None, era_base


# MARK: - Brochures


@dataclass(frozen=True)
class Brochure:
    title: str
    park: str
    """The park as the page names it: ``Yakushima (Island) National Park``."""
    url: str
    category: str
    size: str | None


def brochures(page: str) -> list[Brochure]:
    """The Ministry's English brochures on japan.travel, one per park and one for the
    country."""
    result = []
    for block in re.findall(
        r'<div class="moe-brochures-td-container"(.*?)</a>', page, re.S
    ):
        link = re.search(r'href="([^"]+)"', block)
        title = re.search(r'jnto-moe-brochure-title">(.*?)</span>', block, re.S)
        park = re.search(r'jnto-moe-park-title">(.*?)</span>', block, re.S)
        category = re.search(r'jnto-moe-category-title">(.*?)</span>', block, re.S)
        size = re.search(r'jnto-moe-brochure-size">(.*?)</span>', block, re.S)
        if not (link and title and park):
            continue
        result.append(Brochure(
            title=html.unescape(title.group(1)).strip(),
            park=html.unescape(park.group(1)).strip(),
            url=html.unescape(link.group(1)).strip(),
            category=html.unescape(category.group(1)).strip() if category else "",
            size=html.unescape(size.group(1)).strip() if size else None,
        ))
    return result


def english_key(name: str) -> str:
    """A park's English name reduced for matching: ``Sanriku Fukko (reconstruction)
    National Park`` and ``Sanriku Fukko`` both give ``sanrikufukko``."""
    name = re.sub(r"\([^)]*\)", "", name)
    name = re.sub(r"national park", "", name, flags=re.IGNORECASE)
    return re.sub(r"[^a-z]", "", name.lower())


def pdf_links(page: str, base: str) -> list[tuple[str, str]]:
    """``(link text, absolute URL)`` for every PDF a page links."""
    found = []
    for href, text in re.findall(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', page, re.S):
        url = html.unescape(href)
        if not re.search(r"\.pdf(?:$|[?#])", url, re.IGNORECASE):
            continue
        if url.startswith("/"):
            url = re.match(r"https?://[^/]+", base).group() + url  # type: ignore[union-attr]
        elif not url.startswith("http"):
            url = base.rsplit("/", 1)[0] + "/" + url
        title = re.sub(r"\s+", " ", _strip(text)).strip()
        found.append((re.sub(r"\s*\[PDF\]\s*$", "", title, flags=re.IGNORECASE), url))
    return found


def _strip(fragment: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", " ", fragment))


_JAPANESE = re.compile(r"[぀-ヿ㐀-鿿]")


def document_language(title: str, url: str) -> str:
    """``ja`` for a document whose title is in Japanese or whose address says so,
    otherwise ``en``: the brochure page is the Ministry's English site."""
    if _JAPANESE.search(title) or re.search(r"(?:[/_-](?:ja|jp|japanese)(?:[/_.-]|$))", url):
        return "ja"
    return "en"
