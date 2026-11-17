"""Japan's country package, on small synthetic inputs: no network, no raw store.

Pinned here: the Shapefile and dBASE reader (including Shift_JIS attributes and deleted
rows), the union that turns a park's zones into its outline, OSM multipolygons,
prefecture sampling and Natural Earth's Amami correction, the region rule, identifier
minting through the registries, the Ministry's pages and visitor workbook, and the shape
of the records the app decodes.
"""

from __future__ import annotations

import io
import shutil
import struct
import zipfile
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

from unigrids_pipeline import countries, ids, outline
from unigrids_pipeline.countries.jp import assembly, content, fetching, geometry, moe, shapefile

# MARK: - Synthetic Shapefiles


def _shp(records: list[list[list[tuple[float, float]]]]) -> bytes:
    """A polygon Shapefile: each record a list of rings, closed as the format wants."""
    body = b""
    for number, rings in enumerate(records, start=1):
        closed = [[*ring, ring[0]] for ring in rings]
        points = [point for ring in closed for point in ring]
        parts, start = [], 0
        for ring in closed:
            parts.append(start)
            start += len(ring)
        xs, ys = [x for x, _ in points], [y for _, y in points]
        content_bytes = struct.pack(
            "<i4d2i", 5, min(xs), min(ys), max(xs), max(ys), len(closed), len(points)
        )
        content_bytes += struct.pack(f"<{len(parts)}i", *parts)
        content_bytes += struct.pack(f"<{2 * len(points)}d", *[c for p in points for c in p])
        body += struct.pack(">2i", number, len(content_bytes) // 2) + content_bytes
    header = struct.pack(">7i", 9994, 0, 0, 0, 0, 0, (100 + len(body)) // 2)
    header += struct.pack("<2i", 1000, 5) + struct.pack("<8d", *([0.0] * 8))
    return header + body


def _dbf(
    fields: list[tuple[str, int]],
    rows: list[list[str] | None],
    *,
    encoding: str = "utf-8",
    driver: int = 0,
) -> bytes:
    """A dBASE table of character fields; a ``None`` row is written deleted."""
    header_length = 32 + 32 * len(fields) + 1
    record_length = 1 + sum(length for _, length in fields)
    reserved = bytearray(20)
    reserved[29 - 12] = driver
    header = struct.pack("<B3BIHH", 3, 126, 1, 1, len(rows), header_length, record_length)
    header += bytes(reserved)
    for name, length in fields:
        header += name.encode().ljust(11, b"\x00") + b"C" + bytes(4) + bytes([length, 0])
        header += bytes(14)
    header += b"\x0d"
    body = b""
    for row in rows:
        if row is None:
            body += b"*" + b" " * (record_length - 1)
            continue
        body += b" " + b"".join(
            value.encode(encoding).ljust(length, b" ")[:length]
            for value, (_, length) in zip(row, fields, strict=True)
        )
    return header + body + b"\x1a"


def _zip(path: Path, stem: str, shp: bytes, dbf: bytes, cpg: str | None = None) -> Path:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(f"{stem}.shp", shp)
        archive.writestr(f"{stem}.dbf", dbf)
        if cpg:
            archive.writestr(f"{stem}.cpg", cpg)
    return path


SQUARE_CW = [(0.0, 0.0), (0.0, 2.0), (2.0, 2.0), (2.0, 0.0)]
HOLE_CCW = [(0.5, 0.5), (1.5, 0.5), (1.5, 1.5), (0.5, 1.5)]


def test_shapefile_reads_polygons_holes_and_utf8_attributes(tmp_path):
    shp = _shp([[SQUARE_CW, HOLE_CCW], [[(5.0, 5.0), (5.0, 6.0), (6.0, 6.0), (6.0, 5.0)]]])
    dbf = _dbf([("NAME", 30), ("ZONE", 30)], [["知床", "特別保護地区"], ["尾瀬", "普通地域"]])
    features = shapefile.read_zip(_zip(tmp_path / "nps.zip", "nps", shp, dbf))
    assert [f.attributes for f in features] == [
        {"NAME": "知床", "ZONE": "特別保護地区"},
        {"NAME": "尾瀬", "ZONE": "普通地域"},
    ]
    first = features[0].polygons
    assert len(first) == 1 and len(first[0]) == 2, "one polygon, its hole kept with it"
    assert first[0][0][0] == (0.0, 0.0) and len(first[0][0]) == 4, "closing point dropped"
    assert outline.contains(first, 0.25, 0.25) and not outline.contains(first, 1.0, 1.0)


def test_dbf_reads_shift_jis_by_its_language_driver():
    data = _dbf([("NAME", 20)], [["阿寒摩周"]], encoding="cp932", driver=0x13)
    assert list(shapefile.read_dbf(data)) == [{"NAME": "阿寒摩周"}]


def test_dbf_without_a_driver_falls_back_from_utf8_to_cp932():
    data = _dbf([("NAME", 20)], [["釧路湿原"]], encoding="cp932")
    assert list(shapefile.read_dbf(data)) == [{"NAME": "釧路湿原"}]


def test_a_deleted_row_does_not_shift_the_attributes_onto_the_wrong_shape(tmp_path):
    shp = _shp([[SQUARE_CW], [[(5.0, 5.0), (5.0, 6.0), (6.0, 6.0), (6.0, 5.0)]]])
    dbf = _dbf([("NAME", 10)], [None, ["kept"]])
    features = shapefile.read_zip(_zip(tmp_path / "a.zip", "a", shp, dbf))
    assert len(features) == 1
    assert features[0].attributes == {"NAME": "kept"}
    assert outline.bbox(features[0].polygons) == (5.0, 5.0, 6.0, 6.0)


def test_park_zones_are_joined_to_the_content_list_by_name(tmp_path):
    shp = _shp([[SQUARE_CW], [[(2.0, 0.0), (2.0, 2.0), (4.0, 2.0), (4.0, 0.0)]]])
    dbf = _dbf([("NAME", 20), ("ZONE", 20)], [["知床", "特別保護地区"], ["知床", "普通地域"]])
    path = _zip(tmp_path / "nps.zip", "nps", shp, dbf)
    parks = [{"id": "jp-np-shiretoko", "localName": "知床国立公園"}]
    zones = fetching.park_zones(path, parks)
    assert set(zones["jp-np-shiretoko"]) == {"特別保護地区", "普通地域"}
    with pytest.raises(shapefile.ShapefileError):
        fetching.park_zones(path, [*parks, {"id": "jp-np-oze", "localName": "尾瀬国立公園"}])


# MARK: - Union and multipolygons


def _square(x: float, y: float, size: float = 1.0) -> outline.Polygon:
    return [[(x, y), (x + size, y), (x + size, y + size), (x, y + size)]]


def test_zones_sharing_an_edge_union_into_one_ring():
    merged = geometry.union([_square(0, 0), _square(1, 0)])
    assert len(merged) == 1 and len(merged[0]) == 1
    assert outline.ring_area(merged[0][0]) == pytest.approx(2.0)
    assert outline.bbox(merged) == (0.0, 0.0, 1.0, 2.0)


def test_parts_touching_at_one_corner_stay_two_rings():
    merged = geometry.union([_square(0, 0), _square(1, 1)])
    assert len(merged) == 2
    assert sorted(outline.ring_area(polygon[0]) for polygon in merged) == [1.0, 1.0]


def test_a_frame_of_zones_keeps_the_hole_in_its_middle():
    frame = [
        _square(x, y)
        for x in range(3)
        for y in range(3)
        if (x, y) != (1, 1)
    ]
    merged = geometry.union(frame)
    assert len(merged) == 1 and len(merged[0]) == 2, "one exterior with one hole"
    assert outline.contains(merged, 0.5, 0.5)
    assert not outline.contains(merged, 1.5, 1.5)
    assert outline.geodesic_acres(merged) == pytest.approx(
        sum(outline.geodesic_acres([square]) for square in frame), rel=1e-9
    )


def test_an_osm_relation_joins_its_ways_into_rings_with_a_hole():
    def way(points, role="outer"):
        return {"type": "way", "role": role,
                "geometry": [{"lon": x, "lat": y} for x, y in points]}

    relation = {
        "type": "relation",
        "members": [
            way([(0, 0), (4, 0), (4, 4)]),
            way([(0, 0), (0, 4), (4, 4)]),
            way([(1, 1), (2, 1), (2, 2), (1, 2), (1, 1)], role="inner"),
            {"type": "node", "ref": 1, "role": "label"},
        ],
    }
    polygons = geometry.osm_polygons(relation)
    assert len(polygons) == 1 and len(polygons[0]) == 2
    assert outline.contains(polygons, 3.0, 3.0)
    assert not outline.contains(polygons, 1.5, 1.5)


def test_many_points_against_an_outline_matches_the_one_point_rule():
    polygon = [[*SQUARE_CW], [*HOLE_CCW]]
    points = [(0.25, 0.25), (1.0, 1.0), (3.0, 3.0), (1.75, 0.25)]
    expected = [outline.contains([polygon], x, y) for x, y in points]
    assert list(geometry.contains_many([polygon], points)) == expected


def test_a_town_in_a_hole_of_the_park_is_near_it():
    # A park ten kilometres a side around a village it leaves out, a kilometre square.
    park = [[
        [(140.0, 30.0), (140.1, 30.0), (140.1, 30.1), (140.0, 30.1)],
        [(140.045, 30.045), (140.055, 30.045), (140.055, 30.055), (140.045, 30.055)],
    ]]
    village = (140.05, 30.05)
    assert not geometry.contains_many(park, [village])[0]
    assert geometry.near_many(park, [village], 1_000)[0]
    assert not geometry.near_many(park, [(141.0, 31.0)], 5_000)[0]


# MARK: - Prefectures and regions


def _prefectures() -> geometry.Prefectures:
    return geometry.Prefectures([
        ("JP-20", [[[(0, 0), (10, 0), (10, 10), (0, 10)]]]),
        ("JP-21", [[[(10, 0), (20, 0), (20, 10), (10, 10)]]]),
    ])


def test_prefectures_are_the_ones_holding_a_real_share_largest_first():
    park = [[[(2, 2), (13, 2), (13, 8), (2, 8)]]]
    assert _prefectures().of_polygons(park, 0.05) == ["JP-20", "JP-21"]
    sliver = [[[(2, 2), (10.2, 2), (10.2, 8), (2, 8)]]]
    assert _prefectures().of_polygons(sliver, 0.05) == ["JP-20"]


def test_a_park_out_at_sea_takes_the_nearest_prefecture():
    sea = [[[(25, 2), (26, 2), (26, 3), (25, 3)]]]
    prefectures = _prefectures()
    assert prefectures.of_polygons(sea, 0.05) == []
    assert prefectures.nearest((25.5, 2.5)) == ["JP-21"]


def test_natural_earths_amami_islands_move_from_okinawa_to_kagoshima():
    amami = [[(129.2, 28.1), (129.7, 28.1), (129.7, 28.5), (129.2, 28.5)]]
    iotorishima = [[(128.22, 27.85), (128.24, 27.85), (128.24, 27.87), (128.22, 27.87)]]
    okinawa = [[(127.7, 26.1), (128.3, 26.1), (128.3, 26.9), (127.7, 26.9)]]
    fixed = dict(assembly.amami_in_kagoshima([
        ("JP-46", [[[(130.0, 31.0), (131.0, 31.0), (131.0, 32.0), (130.0, 32.0)]]]),
        ("JP-47", [amami, iotorishima, okinawa]),
    ]))
    assert amami in fixed["JP-46"]
    assert fixed["JP-47"] == [iotorishima, okinawa]


@pytest.mark.parametrize(
    ("code", "region"),
    [
        ("JP-01", "hokkaido"),
        *((f"JP-{n:02d}", "tohoku") for n in range(2, 8)),
        *((f"JP-{n:02d}", "kanto") for n in (*range(8, 15), 19)),
        *((f"JP-{n:02d}", "chubu") for n in (15, 16, 17, 18, 20, 21, 22, 23, 24)),
        *((f"JP-{n:02d}", "kinki") for n in range(25, 31)),
        *((f"JP-{n:02d}", "chugokuShikoku") for n in range(31, 40)),
        *((f"JP-{n:02d}", "kyushu") for n in range(40, 47)),
        ("JP-47", "okinawaAmami"),
    ],
)
def test_each_prefecture_stamps_in_its_region(code, region):
    assert assembly.region_for(code) == region


def test_a_kagoshima_place_in_the_amami_islands_stamps_with_okinawa():
    assert assembly.region_for("JP-46", latitude=28.3) == "okinawaAmami"
    assert assembly.region_for("JP-46", latitude=31.6) == "kyushu"
    with pytest.raises(ValueError):
        assembly.region_for("JP-48")


# MARK: - Identifiers


def test_a_quasi_national_park_is_named_and_identified_from_its_english_article(tmp_path):
    item = {"article": "https://en.wikipedia.org/wiki/Ch%C5%AB%C5%8D_Alps_Quasi-National_Park"}
    assert assembly.english_name(item) == "Chūō Alps"
    assert assembly.english_name({"en": "Abashiri Quasi National Park"}) == "Abashiri"
    registry = ids.Registry(tmp_path / "places.json")
    first = registry.resolve(
        "moe:中央アルプス国定公園", ids.country_place_id("jp", "qnp", "Chūō Alps")
    )
    assert first == "jp-qnp-chuo-alps"
    registry.save()
    again = ids.Registry(tmp_path / "places.json")
    renamed = again.resolve("moe:中央アルプス国定公園", ids.country_place_id("jp", "qnp", "Chuo"))
    assert renamed == "jp-qnp-chuo-alps", "the registry keeps the first answer"


def test_sight_and_hut_identifiers_survive_japanese_names(tmp_path):
    registry = ids.Registry(tmp_path / "pois.json")
    assert assembly.latin_part("Mount Fuji (富士山)") == "Mount Fuji"
    assert assembly.latin_part("知床五湖 Shiretoko Goko") == "Shiretoko Goko"
    assert assembly.latin_part("槍ヶ岳山荘") is None
    sight = ids.country_poi_id(
        registry, "jp", "fuji-hakone-izu", "guide:jp-np-fuji-hakone-izu:Mount Fuji (富士山)",
        assembly.latin_part("Mount Fuji (富士山)"),
    )
    assert sight == "poi-jp-fuji-hakone-izu-mount-fuji"
    hut = ids.country_poi_id(registry, "jp", "chubusangaku", "osm:node/123", None)
    assert hut == "poi-jp-chubusangaku-osm-node-123"
    twin = ids.country_poi_id(registry, "jp", "chubusangaku", "osm:way/9", "Osm Node 123")
    assert twin != hut, "a second source key never takes the first one's identifier"


# MARK: - The Ministry's pages and workbook


def _workbook(rows: dict[int, dict[str, Any]]) -> bytes:
    """A one-sheet .xlsx: ``{row: {"A": value}}``, strings shared, numbers inline."""
    strings: list[str] = []
    cells = []
    for row, values in sorted(rows.items()):
        parts = []
        for column, value in values.items():
            reference = f"{column}{row}"
            if isinstance(value, str):
                strings.append(value)
                parts.append(f'<c r="{reference}" t="s"><v>{len(strings) - 1}</v></c>')
            else:
                parts.append(f'<c r="{reference}"><v>{value}</v></c>')
        cells.append(f'<row r="{row}">{"".join(parts)}</row>')
    main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    package = "http://schemas.openxmlformats.org/package/2006/relationships"
    shared = "".join(
        f"<si><t>{text}</t><rPh><t>ふりがな</t></rPh></si>" for text in strings
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("xl/workbook.xml", (
            f'<workbook xmlns="{main}" xmlns:r="{relationships}"><sheets>'
            '<sheet name="表" sheetId="1" r:id="rId1"/></sheets></workbook>'
        ))
        archive.writestr("xl/_rels/workbook.xml.rels", (
            f'<Relationships xmlns="{package}"><Relationship Id="rId1" '
            'Target="worksheets/sheet1.xml"/></Relationships>'
        ))
        archive.writestr("xl/worksheets/sheet1.xml", (
            f'<worksheet xmlns="{main}"><sheetData>{"".join(cells)}</sheetData></worksheet>'
        ))
        archive.writestr("xl/sharedStrings.xml", f'<sst xmlns="{main}">{shared}</sst>')
    return buffer.getvalue()


def test_the_visitor_table_reads_the_latest_block_in_ten_thousands():
    # Two blocks side by side, as the Ministry prints them: 1971–72, then 2023–24.
    workbook = _workbook({
        3: {"C": "年次", "D": "昭和46年", "E": 47, "H": "年次", "I": "31\n/令和元", "J": 5,
            "K": 6},
        5: {"B": 1, "C": "利尻礼文", "D": 101.7, "G": 1, "H": "利尻礼文", "J": 115.2,
            "K": 115.8},
        6: {"C": "サロベツ", "D": 12, "H": "サロベツ", "J": 38, "K": 44},
        7: {"G": 2, "H": "※日高山脈襟裳\n　十勝", "K": "—"},
        8: {"K": 44},
        9: {"G": "（対前年比％）", "K": 105.4},
        10: {"G": "合　　　計", "K": 34007},
    })
    visitors = moe.park_visitors(workbook, expected=2)
    assert visitors == {
        "利尻礼文サロベツ": moe.AnnualVisitors(year=2024, visitors=440_000),
        "日高山脈襟裳十勝": moe.AnnualVisitors(year=2024, visitors=440_000),
    }


@pytest.mark.parametrize(
    ("cell", "base", "year"),
    [("昭和46年", 0, 1971), (47.0, 1925, 1972), ("平成元", 1925, 1989),
     ("31\n/令和元", 1988, 2019), (6.0, 2018, 2024), (12.0, 0, None)],
)
def test_era_years_read_as_gregorian(cell, base, year):
    assert moe._year(cell, base)[0] == year


QUASI_PAGE = """
<ul class="p-quasiList__list">
  <li class="p-quasiList__item js-inview">
    <ul class="c-tagIconList"><li class="c-tagIconList__tag">長野県</li>
      <li class="c-tagIconList__tag">岐阜県</li></ul>
    <div class="p-quasiList__item__title is-no-PIN">
      <ruby data-ruby="おんたけさん">御嶽山<rt>おんたけさん</rt></ruby>国定公園
    </div>
    <div class="p-quasiList__item__detail">信仰の山</div>
    <div class="p-quasiList__item__button"><a href="https://www.pref.nagano.lg.jp/x.html">詳細</a></div>
  </li>
  <li class="p-quasiList__item js-inview">
    <ul class="c-tagIconList"><li class="c-tagIconList__tag">北海道</li></ul>
    <div class="p-quasiList__item__title is-no-PIN">
      ニセコ<ruby>積丹<rt>しゃこたん</rt></ruby>小樽海岸国定公園</div>
    <div class="p-quasiList__item__detail">火山</div>
  </li>
</ul>
"""


def test_the_quasi_national_park_list_reads_names_prefectures_and_links():
    parks = moe.quasi_parks(QUASI_PAGE, expected=2)
    assert parks[0] == moe.QuasiPark(
        name="御嶽山国定公園", prefectures=["JP-20", "JP-21"], feature="信仰の山",
        url="https://www.pref.nagano.lg.jp/x.html",
    )
    assert parks[1].name == "ニセコ積丹小樽海岸国定公園"
    assert parks[1].prefectures == ["JP-01"] and parks[1].url is None
    with pytest.raises(moe.PageChangedError):
        moe.quasi_parks(QUASI_PAGE)


OFFICE_PAGE = """
<h2 class="p-cont__ttl--3" id="Kyushu"><span>九州地区</span></h2>
<table><tbody>
<tr><td class="c-table-3_td1"><a href="x">屋久島</a></td><td class="c-table-3_td2">全域</td>
<td class="c-table-3_td3"><a href="y">九州環境局</a><br />〒</td></tr>
<tr><td class="c-table-3_td1" rowspan="2"><a href="z">奄美群島</a></td>
<td class="c-table-3_td3">沖縄奄美自然環境事務所<br />〒</td></tr>
<tr><td class="c-table-3_td2">大島郡</td><td class="c-table-3_td3">沖縄奄美自然環境事務所</td></tr>
</tbody></table>
"""


def test_the_office_page_files_okinawa_amami_parks_apart_from_kyushu():
    offices = moe.park_offices(OFFICE_PAGE, expected=2)
    assert offices["屋久島"].regions == ["kyushu"]
    assert offices["奄美群島"].regions == ["okinawaAmami"]
    assert offices["奄美群島"].offices == ["沖縄奄美自然環境事務所"]


def test_brochures_match_parks_by_their_english_names():
    page = (
        '<div class="moe-brochures-td-container" data-area="kyushu"><a href="https://res.'
        'cloudinary.com/x/27-yakushima_abc" class="g"><span class="jnto-moe-category-title">'
        'BROCHURE</span><span class="jnto-moe-brochure-title">Yakushima National Park</span>'
        '<span class="jnto-moe-brochure-size">10.1\xa0MB</span><span class="jnto-moe-park-'
        'title"> Yakushima (Island) National Park</span></a></div>'
    )
    [brochure] = moe.brochures(page)
    assert brochure.category == "BROCHURE"
    assert moe.english_key(brochure.park) == moe.english_key("Yakushima")
    assert moe.english_key("Sanriku Fukko (reconstruction) National Park") == "sanrikufukko"
    assert moe.english_key("Joshin'etsukogen National Park") == "joshinetsukogen"


@pytest.mark.parametrize(
    ("title", "url", "language"),
    [
        ("Yakushima National Park", "https://res.cloudinary.com/x/27-yakushima", "en"),
        ("屋久島国立公園パンフレット", "https://www.env.go.jp/park/yakushima/a.pdf", "ja"),
        ("Map", "https://www.env.go.jp/park/doc/map_jp.pdf", "ja"),
    ],
)
def test_a_document_is_labelled_with_its_language(title, url, language):
    assert moe.document_language(title, url) == language


def test_managing_bodies_read_as_english_phrases():
    assert moe.managing_body(["JP-20"]) == "Nagano Prefecture"
    assert moe.managing_body(["JP-20", "JP-21"]) == "Nagano and Gifu prefectures"
    assert moe.managing_body(["JP-01"]) == "Hokkaido"
    assert moe.managing_body(["JP-13"]) == "Tokyo Metropolitan Government"
    assert moe.prefecture_code("京都") == "JP-26"
    assert moe.prefecture_code("京都府") == "JP-26"
    assert moe.prefecture_code("北海道") == "JP-01"


# MARK: - Text and rail


def test_a_wikipedia_lead_loses_its_japanese_bracket_and_stays_short():
    extract = (
        "Ontakesan Quasi-National Park (御嶽山国定公園, Ontakesan Kokutei Kōen) is a "
        "quasi-national park in Japan. It was established in 2026. Its central feature is "
        "Mount Ontake (3,067 m) . The park spans four municipalities. More follows."
    )
    assert assembly.lead(extract) == (
        "Ontakesan Quasi-National Park is a quasi-national park in Japan. It was "
        "established in 2026. Its central feature is Mount Ontake (3,067 m)."
    )


def test_a_line_is_named_without_its_direction():
    assert assembly.line_name({"name": "JR中央線快速 (東京→高尾)"}) == "JR中央線快速"
    assert assembly.line_name({"name": "x", "name:en": "JR Chuo Line (Tokyo => Takao)"}) == (
        "JR Chuo Line"
    )
    assert assembly.line_name({"name:en": "JR Keiyo Line (Tokyo ↔ Soga)"}) == "JR Keiyo Line"
    assert assembly.line_name({"name:en": "Hitachi (inbound)"}) == "Hitachi"
    assert assembly.line_name({"name:en": "JR Joban Line (Local) (Ueno ↔ Toride)"}) == (
        "JR Joban Line (Local)"
    )
    assert assembly.line_name({}) is None


def _rail() -> assembly.RailNetwork:
    elements = {
        ("relation", 1): {
            "type": "relation", "id": 1, "tags": {"route": "train", "name": "JR大糸線 (上り)"},
            "members": [
                {"type": "node", "ref": 10, "role": "stop"},
                {"type": "way", "ref": 100, "role": ""},
            ],
        },
        ("relation", 4): {
            "type": "relation", "id": 4, "tags": {"route": "train", "name": "北海道の廃止国鉄線"},
            "members": [{"type": "way", "ref": 100, "role": ""}],
        },
        ("relation", 2): {
            "type": "relation", "id": 2, "tags": {"route": "train", "name": "急行"},
            "members": [{"type": "node", "ref": 20, "role": "stop"}],
        },
        ("relation", 3): {
            "type": "relation", "id": 3,
            "tags": {"type": "route_master", "name": "アルピコ交通上高地線"},
            "members": [{"type": "relation", "ref": 2, "role": ""}],
        },
        ("node", 10): {"type": "node", "id": 10, "lat": 36.5, "lon": 137.86,
                       "tags": {"name": "信濃大町"}},
        ("node", 20): {"type": "node", "id": 20, "lat": 36.5040, "lon": 137.8600,
                       "tags": {"name": "信濃大町"}},
        ("way", 100): {"type": "way", "id": 100, "geometry": [
            {"lat": 36.4, "lon": 137.8}, {"lat": 36.5, "lon": 137.86},
            {"lat": 36.7, "lon": 137.9},
        ]},
    }
    return assembly.RailNetwork(elements)


def test_a_station_takes_the_lines_that_stop_beside_it():
    station = {"type": "node", "id": 99, "lat": 36.5005, "lon": 137.8601,
               "tags": {"railway": "station", "name": "信濃大町", "name:en": "Shinano-Omachi"}}
    record = _rail().station(station)
    assert record == {
        "code": "osm:node/99",
        "name": "Shinano-Omachi",
        "location": {"latitude": 36.5005, "longitude": 137.8601},
        "country": "JP",
        "lines": ["JR大糸線", "アルピコ交通上高地線"],
    }
    subway = {"type": "node", "id": 98, "lat": 30.0, "lon": 130.0,
              "tags": {"railway": "station", "station": "subway", "name": "x"}}
    assert _rail().station(subway) is None
    signal = {"type": "node", "id": 97, "lat": 36.5, "lon": 137.86,
              "tags": {"railway": "station", "name": "平野川信号場",
                       "name:en": "Hiranogawa Signal Station"}}
    assert _rail().station(signal) is None


def test_rail_lines_are_one_entry_per_service_with_encoded_paths():
    [line] = _rail().lines()
    assert line["name"] == "JR大糸線"
    assert line["bbox"] == [36.4, 137.8, 36.7, 137.9]
    assert outline.decode(line["paths"][0])[0] == (137.8, 36.4)


# MARK: - Records


class _FakeRaw:
    snapshot = "2026-11-16"

    def __init__(self, commons: Path) -> None:
        self.commons = commons
        self._licences = {
            "Hero.jpg": {"licence": "CC BY-SA 4.0", "artist": "<a href='x'>A. Photographer</a>",
                         "thumbURL": "https://upload.wikimedia.org/hero-1280.jpg",
                         "descriptionURL": "https://commons.wikimedia.org/wiki/File:Hero.jpg"},
            "Second.jpg": {"licence": "GFDL", "artist": "B. Photographer",
                           "thumbURL": "https://upload.wikimedia.org/second-1280.jpg",
                           "descriptionURL": "https://commons.wikimedia.org/wiki/File:Second.jpg"},
            "Lead.jpg": {"licence": "Public domain", "artist": None,
                         "thumbURL": "https://upload.wikimedia.org/lead-1280.jpg",
                         "descriptionURL": "https://commons.wikimedia.org/wiki/File:Lead.jpg"},
        }

    def licences(self) -> dict[str, Any]:
        return self._licences

    def wikidata(self) -> dict[str, Any]:
        return {}

    def summaries(self) -> dict[str, Any]:
        return {"御嶽山国定公園": {
            "type": "standard",
            "extract": "Ontakesan Quasi-National Park is a park in Japan.",
            "content_urls": {"desktop": {
                "page": "https://en.wikipedia.org/wiki/Ontakesan_Quasi-National_Park"}},
        }}

    def linked_image(self, item: dict[str, Any]) -> dict[str, Any] | None:
        return assembly._Raw.linked_image(self, item)  # type: ignore[arg-type]


GUIDE = {
    "placeID": "jp-np-oze",
    "summary": "A high moor between mountains.",
    "facts": {"establishedYear": 2007, "areaHectares": 37200, "bestSeasons": ["summer", "x"],
              "suggestedTime": "Two days", "elevation": 2356},
    "story": ["One."],
    "howItWorks": ["Zoned."],
    "sights": [
        {"name": "Ozegahara (尾瀬ヶ原)", "note": "The moor.", "location": [36.93, 139.24]},
        {"name": "Oze-numa Visitor Centre", "location": [36.93, 139.30],
         "kind": "visitorCentre"},
        {"name": "Mount Shibutsu", "note": "A peak.", "location": [36.90, 139.18],
         "kind": "viewpoint"},
    ],
    "planYourVisit": {"seasonalClosures": ["Roads close in winter"],
                      "seasonalClosureMonths": [11, 12, 1, 2, 3, 4], "permits": []},
    "fees": [{"title": "Cooperation fee", "cost": "¥200", "amount": 200, "currencyCode": "JPY"}],
    "themes": ["theme-wetland", "theme-not-a-theme"],
    "photos": [{"file": "File:Hero.jpg", "caption": "The moor", "altText": "Grass"},
               {"file": "File:Second.jpg"}],
    "sources": [{"title": "Oze", "url": "https://www.env.go.jp/park/oze/"}],
}


def test_a_national_park_leaves_complete(tmp_path, monkeypatch):
    commons = tmp_path / "jp-commons"
    for name in ("Hero.jpg", "Second.jpg"):
        path = fetching.photo_path(commons, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (800, 600)).save(path, "JPEG")
    monkeypatch.setattr(content, "guide", lambda place_id: GUIDE)
    monkeypatch.setattr(assembly, "resize", lambda s, d, size, q: shutil.copy(s, d) and True)
    images = tmp_path / "images"
    images.mkdir()
    park = {"id": "jp-np-oze", "name": "Oze", "slug": "oze", "localName": "尾瀬国立公園",
            "passportRegion": "kanto", "reachedBy": " Shuttle bus from Tokura "}
    polygons = [[[(139.1, 36.8), (139.4, 36.8), (139.4, 36.98), (139.1, 36.98)]]]
    prefectures = geometry.Prefectures([
        ("JP-07", [[[(139.0, 36.9), (139.5, 36.9), (139.5, 37.2), (139.0, 37.2)]]]),
        ("JP-10", [[[(139.0, 36.5), (139.5, 36.5), (139.5, 36.9), (139.0, 36.9)]]]),
    ])
    report = assembly.Report()
    place, guide, pois = assembly._national_park(
        park, polygons, prefectures, {"尾瀬": moe.AnnualVisitors(2024, 170_000)},
        _FakeRaw(commons), images, ids.Registry(tmp_path / "pois.json"), report,
    )
    assert place["id"] == "jp-np-oze" and place["kind"] == "nationalPark"
    assert place["agency"] == "environmentMinistryJapan"
    assert place["managedBy"] == "Ministry of the Environment"
    assert place["country"] == "JP" and place["timeZoneID"] == "Asia/Tokyo"
    assert place["subdivisions"] == ["JP-10", "JP-07"]
    assert place["localNames"] == [{"language": "ja", "text": "尾瀬国立公園"}]
    assert place["reachedBy"] == "Shuttle bus from Tokura"
    assert place["officialURL"] == "https://www.japan.travel/national-parks/parks/oze/"
    assert place["facts"] == {
        "establishedYear": 2007, "areaHectares": 37200, "bestSeasons": ["summer"],
        "suggestedTime": "Two days", "annualVisits": 170_000, "annualVisitsYear": 2024,
    }
    assert place["summarySource"] == "Unigrids"
    hero = place["image"]
    assert hero == guide["hero"]
    assert hero["credit"] == "A. Photographer, via Wikimedia Commons"
    assert hero["licence"] == "CC BY-SA 4.0" and hero["isPublicDomain"] is False
    assert (images / hero["assetName"]).exists()
    [second] = guide["gallery"]
    assert second["licence"] == "GFDL" and second["isPublicDomain"] is False
    assert report.unlicensed == ["Second.jpg (GFDL)"]
    assert place["themes"] == ["theme-wetland"]
    assert report.unknown_themes == ["jp-np-oze: theme-not-a-theme"]

    assert [poi["kind"] for poi in pois] == ["sight", "visitorCentre", "viewpoint"]
    assert [poi["rank"] for poi in pois] == [1, 0, 2]
    assert pois[0]["id"] == "poi-jp-oze-ozegahara"
    assert guide["sightNotes"] == {
        "poi-jp-oze-ozegahara": "The moor.", "poi-jp-oze-mount-shibutsu": "A peak.",
    }
    assert guide["planYourVisit"] == {
        "seasonalClosures": ["Roads close in winter"],
        "seasonalClosureMonths": [11, 12, 1, 2, 3, 4],
    }
    assert guide["fees"] == [
        {"title": "Cooperation fee", "cost": "¥200", "amount": 200, "currencyCode": "JPY"}
    ]
    assert guide["howItWorks"] == ["Zoned."]
    # The outline is nps.zip's; the area is the guide's figure, from MOE's park table.
    assert "Park outline: Ministry of the Environment, Japan (nps.zip, 2026-11-16)" in (
        guide["credits"]
    )
    assert "Park area: 国立公園一覧, Ministry of the Environment, Japan" in guide["credits"]
    assert not any("Park areas" in line for line in guide["credits"])
    assert any("japan.travel" in source["url"] for source in guide["sources"])


def test_a_quasi_national_park_without_an_outline_ships_as_a_point(tmp_path):
    entry = moe.QuasiPark(
        name="御嶽山国定公園", prefectures=["JP-20", "JP-21"], feature=None,
        url="https://www.pref.nagano.lg.jp/x.html",
    )
    item = {
        "qid": "Q141593076", "inception": "2026-04-10T00:00:00Z",
        "article": "https://en.wikipedia.org/wiki/Ontakesan_Quasi-National_Park",
        "coordinate": (35.8823, 137.4486),
        "image": "http://commons.wikimedia.org/wiki/Special:FilePath/Lead.jpg",
    }
    report = assembly.Report()
    place, polygons = assembly._quasi_park(
        entry, item, {}, _FakeRaw(tmp_path), _prefectures(),
        ids.Registry(tmp_path / "places.json"), report,
    )
    assert polygons is None
    assert report.no_outline == ["Ontakesan (御嶽山国定公園)"]
    assert place == {
        "id": "jp-qnp-ontakesan",
        "name": "Ontakesan",
        "designation": "Quasi-National Park",
        "kind": "quasiNationalPark",
        "agency": "prefecture",
        "country": "JP",
        "subdivisions": ["JP-20", "JP-21"],
        "localNames": [{"language": "ja", "text": "御嶽山国定公園"}],
        "passportRegion": "chubu",
        "timeZoneID": "Asia/Tokyo",
        "centre": {"latitude": 35.8823, "longitude": 137.4486},
        "facts": {"establishedYear": 2026},
        "managedBy": "Nagano and Gifu prefectures",
        "officialURL": "https://www.pref.nagano.lg.jp/x.html",
        "summary": "Ontakesan Quasi-National Park is a park in Japan.",
        "summarySource": "Wikipedia",
        "summaryLicence": "CC BY-SA 4.0",
        "summaryURL": "https://en.wikipedia.org/wiki/Ontakesan_Quasi-National_Park",
        "infoURL": "https://en.wikipedia.org/wiki/Ontakesan_Quasi-National_Park",
        "image": {
            # Public domain, and Commons names no author: credited to Commons alone.
            "credit": "Wikimedia Commons",
            "isPublicDomain": True,
            "url": "https://upload.wikimedia.org/lead-1280.jpg",
            "sourceURL": "https://commons.wikimedia.org/wiki/File:Lead.jpg",
        },
    }


def test_an_osm_outline_far_smaller_than_the_published_area_is_refused(tmp_path):
    entry = moe.QuasiPark(name="北九州国定公園", prefectures=["JP-40"], feature=None, url=None)
    item = {"article": "https://en.wikipedia.org/wiki/Kitaky%C5%ABsh%C5%AB_Quasi-National_Park",
            "coordinate": (33.72, 130.767), "areaHectares": 8107.0}
    # About 1 km square: a hundredth of the 8,107 ha the park covers.
    small = [[[(130.95, 33.92), (130.96, 33.92), (130.96, 33.93), (130.95, 33.93)]]]
    report = assembly.Report()
    place, polygons = assembly._quasi_park(
        entry, item, {"北九州国定公園": small}, _FakeRaw(tmp_path), _prefectures(),
        ids.Registry(tmp_path / "places.json"), report,
    )
    assert polygons is None and "extent" not in place
    assert place["centre"] == {"latitude": 33.72, "longitude": 130.767}
    assert report.partial_outlines and "shipped as a point" in report.partial_outlines[0]
    whole = [[[(130.7, 33.7), (130.8, 33.7), (130.8, 33.78), (130.7, 33.78)]]]
    _, kept = assembly._quasi_park(
        entry, item, {"北九州国定公園": whole}, _FakeRaw(tmp_path), _prefectures(),
        ids.Registry(tmp_path / "places2.json"), assembly.Report(),
    )
    assert kept == whole


def test_a_photograph_without_a_licence_is_still_refused():
    with pytest.raises(Exception, match="credit"):
        assembly._photo_entry({"url": "x", "credit": "A", "licence": ""})


def test_japan_keeps_the_country_contract():
    assert "jp" in countries.KNOWN and countries.DEFAULT == ("us",)
    jp = countries.load("jp")
    assert jp.CODE == "jp" and jp.NAME == "Japan"
    assert callable(jp.fetch) and callable(jp.assemble)
    note = jp.manifest_note(
        [{"kind": "nationalPark"}] * 35 + [{"kind": "quasiNationalPark"}] * 58
    )
    assert note.startswith("Japan: all 35 national parks") and "58 quasi-national parks" in note


def test_the_content_list_holds_35_parks_with_unique_ids_and_known_regions():
    parks = content.national_parks()
    assert len(parks) == 35
    assert len({park["id"] for park in parks}) == 35
    assert all(park["id"].startswith("jp-np-") for park in parks)
    assert {park["passportRegion"] for park in parks} <= {
        "hokkaido", "tohoku", "kanto", "chubu", "kinki", "chugokuShikoku", "kyushu",
        "okinawaAmami",
    }
    assert all(park["localName"].endswith("国立公園") for park in parks)


# MARK: - Sources as fetched


def test_wikidata_rows_flatten_to_one_item_per_japanese_label():
    payload = {"results": {"bindings": [
        {"item": {"value": "http://www.wikidata.org/entity/Q141593076"},
         "class": {"value": "http://www.wikidata.org/entity/Q11832860"},
         "ja": {"value": "御嶽山国定公園"},
         "article": {"value": "https://en.wikipedia.org/wiki/Ontakesan_Quasi-National_Park"},
         "coord": {"value": "Point(137.448619 35.882291)"},
         "inception": {"value": "2026-04-10T00:00:00Z"}},
        {"item": {"value": "http://www.wikidata.org/entity/Q141593076"},
         "ja": {"value": "御嶽山国定公園"},
         "coord": {"value": "Point(1 2)"},
         "image": {"value": "http://commons.wikimedia.org/wiki/Special:FilePath/A%20b.jpg"}},
        {"item": {"value": "http://www.wikidata.org/entity/Q1"}},
    ]}}
    items = fetching.wikidata_items(payload)
    assert list(items) == ["御嶽山国定公園"]
    item = items["御嶽山国定公園"]
    assert item["qid"] == "Q141593076" and item["class"] == "Q11832860"
    assert item["coordinate"] == (35.882291, 137.448619), "the first coordinate is kept"
    assert fetching.commons_name(item["image"]) == "A b.jpg"
    assert fetching.commons_name("File:Mount_Fuji.jpg") == "Mount Fuji.jpg"


def test_quasi_outlines_come_from_protected_areas_relations_first(monkeypatch):
    square = [{"lon": x, "lat": y} for x, y in [(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]]
    payload = {"elements": [
        {"type": "way", "id": 1, "geometry": square,
         "tags": {"name": "琵琶湖国定公園", "leisure": "nature_reserve"}},
        {"type": "relation", "id": 2,
         "members": [{"type": "way", "role": "outer", "geometry": square}],
         "tags": {"name": "琵琶湖国定公園", "boundary": "protected_area",
                  "wikidata": "Q3133264"}},
        {"type": "way", "id": 3, "geometry": square,
         "tags": {"name": "網走国定公園"}},
    ]}
    monkeypatch.setattr(assembly, "_json", lambda source, name: payload)
    found = assembly._Raw(Path("raw/2026-11-16/jp-biodic")).quasi_outlines()
    assert set(found) == {"琵琶湖国定公園", "Q3133264"}, "an untagged way is not an outline"
    assert len(found["琵琶湖国定公園"]) == 1, "the relation, not the relation and the way"


def test_stations_a_service_lists_as_stops_stand_in_when_a_park_has_no_answer():
    network = _rail()
    assert network.member_stations() == []
    station = {"type": "node", "id": 30, "lat": 36.6, "lon": 137.9,
               "tags": {"railway": "station", "name": "白馬"}}
    network._elements[("node", 30)] = station
    assert network.member_stations() == [station]


def test_stops_in_nested_brackets_or_none_are_dropped():
    assert assembly.line_name({"name:en": (
        "Nishitetsu Tenjin Omuta Line Limited Express (Nishitetsu Fukuoka (Tenjin) => Omuta)"
    )}) == "Nishitetsu Tenjin Omuta Line Limited Express"
    chuo = {"name": "JR中央線・青梅線\u3000立川 => 西立川"}
    assert assembly.line_name(chuo) == "JR中央線・青梅線"
    assert assembly.line_name({"name": "普通 郡山<=>福島"}) == "普通"
    assert assembly.line_name({"name": "JR大糸線"}) == "JR大糸線"


def test_a_route_named_by_its_stops_after_a_colon_loses_them():
    assert assembly.line_name({"name:en": "Kodama: Shin-Osaka => Okayama => Hakata"}) == "Kodama"
    assert assembly.line_name({"name:en": "Tsubame: Hakata <=> Kagoshima-chuo"}) == "Tsubame"


def test_shinkansen_track_is_named_by_its_line():
    assert assembly.shinkansen_line({"name": "山陽新幹線;広島;14番線"}) == "Sanyo Shinkansen"
    assert assembly.shinkansen_line({"name": "西九州新幹線"}) == "Nishi-Kyushu Shinkansen"
    assert assembly.shinkansen_line({"name": "JR奥羽本線 (山形新幹線)"}) == "Yamagata Shinkansen"
    assert assembly.shinkansen_line({"name": "海峡線・北海道新幹線"}) == "Hokkaido Shinkansen"
    assert assembly.shinkansen_line({"name": "JR中央線"}) is None


def _shinkansen() -> assembly.RailNetwork:
    """Two services over two lines meeting at Tokyo: names come from the track."""
    def way(way_id, name, points):
        return ("way", way_id), {
            "type": "way", "id": way_id, "tags": {"name": name, "highspeed": "yes"},
            "geometry": [{"lat": lat, "lon": lon} for lat, lon in points],
        }

    elements = dict([
        way(1, "東海道新幹線", [(35.681, 139.767), (35.0, 138.5)]),
        way(2, "山陽新幹線", [(34.733, 135.5), (34.4, 133.0)]),
        way(3, "東北新幹線", [(35.681, 139.767), (36.5, 140.0)]),
    ])
    elements[("relation", 10)] = {
        "type": "relation", "id": 10, "tags": {"route": "train", "name": "のぞみ"},
        "members": [
            {"type": "node", "ref": 100, "role": "stop"},
            {"type": "way", "ref": 1, "role": ""}, {"type": "way", "ref": 2, "role": ""},
        ],
    }
    elements[("relation", 11)] = {
        "type": "relation", "id": 11,
        "tags": {"route": "train", "name:en": "JR Shinkansen (Hayabusa Train)"},
        "members": [
            {"type": "node", "ref": 100, "role": "stop"},
            {"type": "way", "ref": 3, "role": ""}, {"type": "way", "ref": 1, "role": ""},
        ],
    }
    elements[("node", 100)] = {"type": "node", "id": 100, "lat": 35.6812, "lon": 139.7671,
                               "tags": {"name": "東京"}}
    return assembly.RailNetwork(elements)


def test_shinkansen_lines_are_drawn_once_per_line_not_per_service():
    names = [line["name"] for line in _shinkansen().lines()]
    assert names == ["Sanyo Shinkansen", "Tohoku Shinkansen", "Tokaido Shinkansen"]


def test_tokyo_lists_the_shinkansen_lines_that_meet_there():
    tokyo = {"type": "node", "id": 900, "lat": 35.6812, "lon": 139.7671,
             "tags": {"railway": "station", "name": "東京", "name:en": "Tokyo"}}
    record = _shinkansen().station(tokyo)
    assert record is not None
    assert record["lines"] == ["Tohoku Shinkansen", "Tokaido Shinkansen"]
