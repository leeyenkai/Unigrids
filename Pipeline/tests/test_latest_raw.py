"""A snapshot whose fetch was cut off is never read as if it were whole."""

import json

import pytest

from unigrids_pipeline import config
from unigrids_pipeline.countries.common import latest_raw


def _snapshot(root, date, source, files, *, finished):
    directory = root / date / source
    directory.mkdir(parents=True)
    for name in files:
        (directory / name).write_text("[]")
    if finished:
        (directory / "source.json").write_text(json.dumps({"source": {}}))


def test_an_unfinished_newer_fetch_is_passed_over(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path)
    _snapshot(tmp_path, "2026-10-22", "nps-api", ["parks.json"], finished=True)
    _snapshot(tmp_path, "2026-11-17", "nps-api", ["parks.json"], finished=False)
    assert latest_raw("nps-api").name == "2026-10-22"


def test_a_snapshot_missing_a_required_file_is_passed_over(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path)
    _snapshot(tmp_path, "2026-10-22", "nps-api", ["parks.json", "places.json"], finished=True)
    _snapshot(tmp_path, "2026-11-17", "nps-api", ["parks.json"], finished=True)
    assert latest_raw("nps-api", "places.json").name == "2026-10-22"
    assert latest_raw("nps-api").name == "2026-11-17"


def test_no_finished_snapshot_stops_the_build(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path)
    _snapshot(tmp_path, "2026-11-17", "nps-api", ["parks.json"], finished=False)
    with pytest.raises(SystemExit):
        latest_raw("nps-api")
