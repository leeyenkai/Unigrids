"""Writing a pack's tiles as MBTiles.

One SQLite file per park rather than a directory of thousands of small files. Three
reasons, in order of how much they matter:

1. **It is read-only SQLite**, which is what §13 already says the bundled dataset is.
2. **No per-file overhead.** A 12 KB tile in an APFS directory still occupies a 4 KB
   block boundary and an inode; eight thousand of those per park, across 63 parks, is real
   money against a 4 GB limit.
3. Apple's build tooling does not have to walk and sign a quarter of a million files.

MBTiles numbers rows from the *south* (TMS) while ``MKTileOverlay`` asks for them from the
north (XYZ), so the row is flipped on the way in. That one line is the most common bug in
anything that reads an MBTiles file, which is why the pack's manifest states the
convention rather than leaving the app to find out.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any

from .geo import BoundingBox, flip_tile_row

SCHEMA = """
CREATE TABLE metadata (name TEXT, value TEXT);
CREATE TABLE tiles (
    zoom_level  INTEGER,
    tile_column INTEGER,
    tile_row    INTEGER,
    tile_data   BLOB
);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
CREATE UNIQUE INDEX name ON metadata (name);
"""


class MBTilesWriter:
    """Accumulates tiles and writes the metadata MBTiles 1.3 requires."""

    def __init__(self, path: Path) -> None:
        self.path = path
        if path.exists():
            path.unlink()
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.executescript(SCHEMA)
        self.tile_bytes = 0
        self.tile_count = 0

    def __enter__(self) -> MBTilesWriter:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def add(self, zoom: int, x: int, y: int, data: bytes) -> None:
        """Add an XYZ tile. The row is flipped to TMS on the way in."""
        self.connection.execute(
            "INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
            (zoom, x, flip_tile_row(zoom, y), sqlite3.Binary(data)),
        )
        self.tile_bytes += len(data)
        self.tile_count += 1

    def set_metadata(self, **values: Any) -> None:
        self.connection.executemany(
            "INSERT OR REPLACE INTO metadata VALUES (?, ?)",
            [(name, str(value)) for name, value in values.items()],
        )

    def describe(
        self,
        *,
        name: str,
        description: str,
        tile_format: str,
        bounds: BoundingBox,
        min_zoom: int,
        max_zoom: int,
        attribution: str,
        version: str = "1.0.0",
    ) -> None:
        centre_longitude, centre_latitude = bounds.centre
        self.set_metadata(
            name=name,
            description=description,
            # MBTiles only knows png, jpg, pbf and webp: a 256-colour PNG is still a PNG.
            format="png" if tile_format == "png8" else tile_format,
            bounds=",".join(f"{value:.6f}" for value in bounds.as_list()),
            center=f"{centre_longitude:.6f},{centre_latitude:.6f},{min_zoom}",
            minzoom=min_zoom,
            maxzoom=max_zoom,
            type="baselayer",
            version=version,
            attribution=attribution,
        )

    def bytes_by_zoom(self) -> dict[int, dict[str, int]]:
        """Tile count and total tile bytes per zoom — the pilot's headline numbers."""
        rows = self.connection.execute(
            "SELECT zoom_level, COUNT(*), SUM(LENGTH(tile_data)), "
            "MIN(LENGTH(tile_data)), MAX(LENGTH(tile_data)) "
            "FROM tiles GROUP BY zoom_level ORDER BY zoom_level"
        ).fetchall()
        return {
            int(zoom): {
                "tiles": int(count),
                "bytes": int(total or 0),
                "smallest_tile_bytes": int(smallest or 0),
                "largest_tile_bytes": int(largest or 0),
            }
            for zoom, count, total, smallest, largest in rows
        }

    def close(self) -> None:
        self.connection.commit()
        self.connection.execute("VACUUM")
        self.connection.close()
