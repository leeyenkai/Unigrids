"""The countries the reference dataset can cover, one package each.

``reference --countries us,jp`` names the countries a build covers. The dataset holds
exactly those: the build writes each file whole, so a country left out of a run is left
out of what it writes. See ``Pipeline/README.md`` for what a country package provides.
"""

from __future__ import annotations

import importlib
from typing import cast

from .base import BuildContext, Contribution, Country

__all__ = ["DEFAULT", "KNOWN", "BuildContext", "Contribution", "Country", "load", "parse"]

# Each package is imported only when a build asks for it, so a US build never loads
# another country's code or needs its dependencies.
KNOWN = ("us", "jp", "no", "nz", "ca", "au")
DEFAULT = ("us",)


def parse(text: str) -> tuple[str, ...]:
    """``"us, jp"`` → ``("us", "jp")``, in the order given and without repeats."""
    codes: list[str] = []
    for part in text.split(","):
        code = part.strip().lower()
        if not code:
            continue
        if code not in KNOWN:
            raise ValueError(f"no country {code!r}; known: {', '.join(KNOWN)}")
        if code not in codes:
            codes.append(code)
    if not codes:
        raise ValueError(f"name at least one country; known: {', '.join(KNOWN)}")
    return tuple(codes)


def load(code: str) -> Country:
    if code not in KNOWN:
        raise ValueError(f"no country {code!r}; known: {', '.join(KNOWN)}")
    return cast(Country, importlib.import_module(f".{code}", __name__))
