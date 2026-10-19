"""The tile style: a topo-style park map that echoes NPS cartography.

``SPECIFICATION.md`` §8 asks for tiles "styled to echo NPS cartography". What that means
concretely, from the Unigrid brochure maps:

* **Relief shading, not contour lines.** The NPS park map's terrain is a shaded relief
  with a flat land tint over it. Contours are a USGS quadrangle's language, not a park
  brochure's, and they would also be the single most expensive thing on the tile to
  compress.
* **A warm, pale land tint**, dark grey roads with a white casing, muted blue water, and
  trails as a fine dashed brown line.
* **No NPS arrowhead and no seal** — a registered trademark, and using it needs the
  Director's written permission (``AGENTS.md`` §5). This is a style in the same spirit,
  drawn from scratch; it is not NPS artwork.

The elevation tint is a **fixed national ramp** rather than one stretched to each park's
own range. Stretching would look better park by park and make the same elevation a
different colour in Zion and in Rocky Mountain — and two adjacent packs would not meet.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

Colour = tuple[int, int, int]

# Elevation (metres) to land tint. Deliberately low-contrast: the relief shading is what
# carries the terrain, and a loud ramp would both fight it and cost bytes in every tile.
ELEVATION_STOPS: tuple[tuple[float, Colour], ...] = (
    (0.0, (226, 231, 219)),
    (900.0, (233, 230, 212)),
    (1800.0, (237, 228, 208)),
    (2700.0, (239, 232, 222)),
    (3600.0, (244, 242, 238)),
    (4500.0, (248, 248, 246)),
)

NO_ELEVATION = (240, 238, 232)
"""Where the elevation model has no data. A flat tint, so a hole in the DEM reads as
"nothing known here" rather than as flat ground at sea level."""

WATER_FILL: Colour = (183, 212, 227)
WATER_EDGE: Colour = (143, 180, 202)
ROAD_CASING: Colour = (252, 251, 248)
ROAD_MAJOR: Colour = (86, 84, 79)
ROAD_MINOR: Colour = (120, 116, 108)
ROAD_TRACK: Colour = (150, 143, 131)
TRAIL: Colour = (122, 78, 48)
BOUNDARY: Colour = (96, 122, 92)

SHADE_FLOOR = 0.62
"""How dark the deepest shadow goes, as a multiplier on the land tint."""
SHADE_CEILING = 1.34
"""And how bright a sunlit slope gets. Above 1.0 so ridges lift off the page."""


@dataclass(frozen=True)
class LineStyle:
    """How one class of line is drawn, and how it grows with zoom."""

    colour: Colour
    width_at_z14: float
    casing_colour: Colour | None = None
    casing_extra_width: float = 0.0
    dash_pattern: tuple[float, float] | None = None
    min_zoom: int = 0

    def width(self, zoom: int) -> float:
        """Lines thicken with zoom, but less than the ground does.

        A road that scaled with the ground would be a hairline at a park-wide zoom and a
        motorway-wide band at trail zoom. Half a pixel per zoom level keeps it legible at
        both ends.
        """
        return max(0.7, self.width_at_z14 + (zoom - 14) * 0.5)


ROAD_STYLES: dict[str, LineStyle] = {
    "major": LineStyle(ROAD_MAJOR, 2.6, ROAD_CASING, 2.2),
    "minor": LineStyle(ROAD_MINOR, 1.7, ROAD_CASING, 1.6, min_zoom=12),
    "track": LineStyle(ROAD_TRACK, 1.0, None, 0.0, min_zoom=13),
}

TRAIL_STYLE = LineStyle(TRAIL, 1.6, None, 0.0, dash_pattern=(7.0, 4.0))
WATER_LINE_STYLE = LineStyle(WATER_EDGE, 1.4, min_zoom=12)
WATER_EDGE_STYLE = LineStyle(WATER_EDGE, 1.0)
BOUNDARY_STYLE = LineStyle(BOUNDARY, 1.4, dash_pattern=(10.0, 6.0), min_zoom=11)


def land_tint(elevation: np.ndarray) -> np.ndarray:
    """The land colour for an elevation patch, as ``height × width × 3`` uint8."""
    heights = np.array([stop for stop, _ in ELEVATION_STOPS])
    filled = np.where(np.isfinite(elevation), elevation, 0.0)
    channels = []
    for channel in range(3):
        values = np.array([colour[channel] for _, colour in ELEVATION_STOPS], dtype=np.float32)
        interpolated = np.interp(filled, heights, values)
        channels.append(np.where(np.isfinite(elevation), interpolated, NO_ELEVATION[channel]))
    return np.clip(np.stack(channels, axis=-1), 0, 255).astype(np.uint8)


def shade(tint: np.ndarray, hillshade: np.ndarray) -> np.ndarray:
    """Multiply the land tint by the relief shading."""
    factor = SHADE_FLOOR + (SHADE_CEILING - SHADE_FLOOR) * hillshade[..., None]
    return np.clip(tint.astype(np.float32) * factor, 0, 255).astype(np.uint8)
