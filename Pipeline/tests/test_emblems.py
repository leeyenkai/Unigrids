"""The stamps' pictures: every drawing the app can draw as authored, and every place's own
picture named on its record."""

from pathlib import Path

import pytest

from unigrids_pipeline import emblems

SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" data-subject="{subject}">'
    "{body}</svg>"
)


def _write(tmp_path: Path, name: str, body: str, *, box="0 0 100 60", subject="a peak") -> Path:
    path = tmp_path / f"{name}.svg"
    path.write_text(SVG.format(box=box, subject=subject, body=body))
    return path


def test_a_drawing_is_read_as_lines_and_solid_areas(tmp_path):
    path = _write(tmp_path, "np-x", '<path d="M0 0 L10 10"/><path class="fill" d="M1 1 h2 v2 z"/>')
    assert emblems.read(path) == {
        "subject": "a peak", "width": 100, "height": 60,
        "parts": [{"d": "M0 0 L10 10", "fill": False}, {"d": "M1 1 h2 v2 z", "fill": True}],
    }


@pytest.mark.parametrize("body, box, subject", [
    ('<path d="M0 0 L1 1"/>', "0 0 50 50", "x"),
    ('<path d="M0 0 A5 5 0 0 1 10 10"/>', "0 0 100 60", "x"),
    ("", "0 0 100 60", "x"),
    ('<path d="M0 0 L1 1"/>', "0 0 100 60", ""),
])
def test_a_drawing_the_app_could_not_draw_is_refused(tmp_path, body, box, subject):
    with pytest.raises(emblems.EmblemError):
        emblems.read(_write(tmp_path, "bad", body, box=box, subject=subject))


def test_a_park_with_a_drawing_names_it_and_one_without_is_reported():
    places = [
        {"id": "np-yosemite", "kind": "nationalPark"},
        {"id": "np-zion", "kind": "nationalPark"},
        {"id": "sp-x", "kind": "statePark"},
    ]
    missing = emblems.attach(places, {"np-yosemite": {}})
    assert places[0]["emblem"] == "np-yosemite"
    assert "emblem" not in places[1] and "emblem" not in places[2]
    assert missing == ["np-zion"]


def test_every_bundled_drawing_reads():
    drawn = emblems.load()
    assert all(entry["parts"] for entry in drawn.values())
    for motif in ("peaks", "monument", "house", "cannon", "memorial", "lighthouse", "lake",
                  "river", "road", "flag", "trees", "forest", "prairie", "marsh", "mesa", "rock"):
        assert f"motif-{motif}" in drawn, motif
