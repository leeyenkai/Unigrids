import Foundation
import SQLite3
import Testing
import UnigridsCore
@testable import UnigridsReference

@Suite("Offline packs")
struct OfflinePackTests {
    /// A one-tile MBTiles file: zoom 2, column 1, TMS row 2 — XYZ row 1.
    private func makePack(in folder: URL) throws -> URL {
        let url = folder.appending(path: "tiles.mbtiles")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path(percentEncoded: false), &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = "CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, "
            + "tile_row INTEGER, tile_data BLOB); "
            + "INSERT INTO tiles VALUES (2, 1, 2, x'0102030405');"
        #expect(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)
        return url
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "unigrids-packs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a tile is found by its XYZ address, the TMS row flipped")
    func readsTiles() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try MBTilesReader(url: makePack(in: root))
        #expect(reader.tile(zoom: 2, column: 1, row: 1) == Data([1, 2, 3, 4, 5]))
        #expect(reader.tile(zoom: 2, column: 1, row: 2) == nil)
        #expect(reader.tile(zoom: 3, column: 1, row: 1) == nil)
    }

    @Test("the catalogue reads the index and manifests, and skips a pack without tiles")
    func catalogue() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let zion = root.appending(path: "np-zion")
        let gone = root.appending(path: "np-acadia")
        for pack in [zion, gone] {
            try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
            let manifest = """
            {"name": "Pack", "bounds": {"park": [-113.2, 37.1, -112.9, 37.5],
             "rendered": [-113.3, 37.0, -112.8, 37.6]},
             "tiles": {"file": "tiles.mbtiles", "minZoom": 10, "maxZoom": 16}}
            """
            try Data(manifest.utf8).write(to: pack.appending(path: "manifest.json"))
        }
        _ = try makePack(in: zion)
        let index = """
        {"packs": [{"placeID": "np-zion", "name": "Zion National Park", "bytes": 100},
                   {"placeID": "np-acadia", "name": "Acadia National Park", "bytes": 100}]}
        """
        try Data(index.utf8).write(to: root.appending(path: "index.json"))

        let catalogue = OfflinePackCatalogue(root: root)
        #expect(catalogue.packs.map(\.placeID) == ["np-zion"])
        let pack = try #require(catalogue.pack(for: "np-zion"))
        #expect(pack.name == "Zion National Park")
        #expect(pack.maxZoom == 16)
        #expect(pack.park == BoundingBox(south: 37.1, west: -113.2, north: 37.5, east: -112.9))
    }

    @Test("no folder, or an empty one, is an empty catalogue")
    func empty() throws {
        #expect(OfflinePackCatalogue(root: nil).packs.isEmpty)
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(OfflinePackCatalogue(root: root).packs.isEmpty)
    }
}
