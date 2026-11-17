"""Which Overpass answers are kept: a partial one must never pass for the whole."""

from __future__ import annotations

import pytest

from unigrids_pipeline.sources import http, osm

_PARTIAL = {
    "elements": [{"type": "way", "id": 1}],
    "remark": "runtime error: Query timed out in \"query\" at line 3 after 301 seconds.",
}
_WHOLE = {"elements": [{"type": "way", "id": 1}, {"type": "way", "id": 2}]}


class _Response:
    def __init__(self, payload: dict) -> None:
        self._payload = payload

    def json(self) -> dict:
        return self._payload


def _answers(monkeypatch, by_endpoint: dict[str, dict]) -> list[str]:
    asked: list[str] = []

    def post(session, url, **_):
        asked.append(url)
        return _Response(by_endpoint[url])

    monkeypatch.setattr(osm.http, "post", post)
    return asked


def test_a_partial_answer_is_refused_and_the_next_endpoint_asked(monkeypatch):
    asked = _answers(monkeypatch, {"https://a": _PARTIAL, "https://b": _WHOLE})
    payload = osm.download_query(None, "query", endpoints=("https://a", "https://b"))
    assert payload == _WHOLE
    assert asked == ["https://a", "https://b"]


def test_only_partial_answers_fail_the_query(monkeypatch):
    _answers(monkeypatch, {"https://a": _PARTIAL, "https://b": _PARTIAL})
    with pytest.raises(http.FetchError, match="partial answer"):
        osm.download_query(None, "query", endpoints=("https://a", "https://b"))


def test_an_informational_remark_is_not_an_error(monkeypatch):
    remarked = {**_WHOLE, "remark": "runtime remark: Timeout is 300 and maxsize is 512 MB."}
    _answers(monkeypatch, {"https://a": remarked})
    assert osm.download_query(None, "query", endpoints=("https://a",)) == remarked
