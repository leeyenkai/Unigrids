from unigrids_pipeline import outline
from unigrids_pipeline.reference_content import choose_photos, is_public_domain_credit

SQUARE = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]


def test_polyline_round_trips_at_five_places():
    ring = [(-112.98765, 37.12345), (-112.9, 37.2), (-113.00001, 37.29999)]
    decoded = outline.decode(outline.encode(ring))
    assert len(decoded) == len(ring)
    for (lon_a, lat_a), (lon_b, lat_b) in zip(decoded, ring, strict=True):
        assert abs(lon_a - lon_b) < 1e-5
        assert abs(lat_a - lat_b) < 1e-5


def test_the_reference_encoding_matches_the_published_example():
    # The format's own worked example: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453).
    ring = [(-120.2, 38.5), (-120.95, 40.7), (-126.453, 43.252)]
    assert outline.encode(ring) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"


def test_simplify_keeps_corners_and_drops_collinear_points():
    ring = [(0.0, 0.0), (0.5, 0.0), (1.0, 0.0), (1.0, 1.0), (0.5, 1.0), (0.0, 1.0)]
    simplified = outline.simplify(ring, 0.01)
    assert (0.5, 0.0) not in simplified
    assert (1.0, 1.0) in simplified


def test_generalise_drops_specks_but_keeps_a_park_of_small_islands():
    speck = [(5.0, 5.0), (5.00001, 5.0), (5.00001, 5.00001), (5.0, 5.00001)]
    kept = outline.generalise([[SQUARE], [speck]], tolerance=0.001)
    assert len(kept) == 1
    islands = [[[(x, 0.0), (x + 0.01, 0.0), (x + 0.01, 0.01), (x, 0.01)]] for x in range(3)]
    assert len(outline.generalise(islands, tolerance=0.001)) == 3


def test_label_point_lands_inside_a_horseshoe():
    horseshoe = [
        (0.0, 0.0), (3.0, 0.0), (3.0, 3.0), (2.0, 3.0), (2.0, 1.0),
        (1.0, 1.0), (1.0, 3.0), (0.0, 3.0),
    ]
    lat, lon = outline.label_point([[horseshoe]])
    assert outline.contains([[horseshoe]], lon, lat)


def test_contains_respects_holes():
    hole = [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)]
    assert outline.contains([[SQUARE, hole]], 0.1, 0.1)
    assert not outline.contains([[SQUARE, hole]], 0.5, 0.5)


def test_only_nps_credited_photos_are_public_domain():
    assert is_public_domain_credit("NPS Photo / Shane Carte")
    assert is_public_domain_credit("NPS/Jacob W. Frank")
    assert is_public_domain_credit("National Park Service")
    assert not is_public_domain_credit("© Jane Doe")
    assert not is_public_domain_credit("NPS Photo courtesy of a volunteer")
    assert not is_public_domain_credit("Photo by Jane Doe")
    assert not is_public_domain_credit(None)


def test_choose_photos_keeps_the_nps_order_and_skips_others():
    images = [
        {"url": "a", "credit": "© Someone"},
        {"url": "b", "credit": "NPS Photo"},
        {"url": "b", "credit": "NPS Photo"},
        {"url": "c", "credit": "NPS / Ranger"},
    ]
    assert [image["url"] for image in choose_photos(images)] == ["b", "c"]


def test_geodesic_area_of_a_one_degree_square_at_the_equator():
    ring = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    acres = outline.geodesic_acres([[ring]])
    # 111.2 km × 110.6 km ≈ 12,364 km², about 3.055 million acres.
    assert 3.0e6 < acres < 3.1e6


def test_geodesic_area_subtracts_holes():
    outer = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    hole = [(0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75)]
    assert outline.geodesic_acres([[outer, hole]]) < 0.8 * outline.geodesic_acres([[outer]])


def test_photo_choice_skips_phrases_and_recaptions_slogans():
    images = [
        {"url": "a", "title": "Entrance Fee Required Year-Round", "credit": "NPS Photo"},
        {"url": "b", "title": "Animal Crossing", "credit": "NPS Photo"},
    ]
    chosen = choose_photos(
        images, skip=["Entrance Fee"], captions={"Animal Crossing": "Wildlife crossing"}
    )
    assert [(image["url"], image["title"]) for image in chosen] == [("b", "Wildlife crossing")]
