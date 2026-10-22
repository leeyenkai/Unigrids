import Foundation
import SQLite3
import Synchronization
import UnigridsCore

// Offline park packs (SPECIFICATION.md §8, docs/adr/0006 and 0010): topographic tiles for
// a national park, rendered by the pipeline and shipped inside the app, so the park's map
// works with no connection at all.

/// One park's pack: where its tiles are, what they cover, and what they owe.
public struct OfflinePack: Sendable, Hashable, Identifiable {
    public let placeID: UnigridsID
    public let name: String
    /// The size of the pack on disk.
    public let bytes: Int
    public let minZoom: Int
    public let maxZoom: Int
    /// What the tiles cover: the park and a buffer around it.
    public let rendered: BoundingBox
    /// The park itself, for framing.
    public let park: BoundingBox
    /// The credit the tiles must carry wherever they are shown.
    public let attribution: String
    public let tilesURL: URL

    public var id: UnigridsID {
        placeID
    }
}

/// The packs the app carries, read from the bundle's `OfflinePacks` folder. A build with no
/// packs is a valid build: the catalogue is empty and the app says offline maps are not
/// included.
public struct OfflinePackCatalogue: Sendable {
    public let packs: [OfflinePack]

    /// The catalogue in the app's own bundle.
    public static let bundled = OfflinePackCatalogue(
        root: Bundle.main.url(forResource: "OfflinePacks", withExtension: nil)
    )

    public init(root: URL?) {
        guard let root,
              let data = try? Data(contentsOf: root.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data)
        else {
            packs = []
            return
        }
        packs = index.packs.compactMap { entry in
            let folder = root.appending(path: entry.placeID)
            guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  let rendered = manifest.bounds.rendered.box,
                  let park = manifest.bounds.park.box
            else { return nil }
            let tiles = folder.appending(path: manifest.tiles.file)
            guard FileManager.default.fileExists(atPath: tiles.path(percentEncoded: false))
            else { return nil }
            return OfflinePack(
                placeID: UnigridsID(entry.placeID),
                name: entry.name ?? manifest.name,
                bytes: entry.bytes,
                minZoom: manifest.tiles.minZoom,
                maxZoom: manifest.tiles.maxZoom,
                rendered: rendered,
                park: park,
                attribution: Self.attribution,
                tilesURL: tiles
            )
        }
    }

    public func pack(for placeID: UnigridsID) -> OfflinePack? {
        packs.first { $0.placeID == placeID }
    }

    /// The tiles' sources, as each pack's ATTRIBUTION.md sets them out.
    static let attribution = "Elevation USGS 3DEP · Roads and water © OpenStreetMap "
        + "contributors (ODbL) · Trails NPS"

    private struct Index: Decodable {
        struct Entry: Decodable {
            let placeID: String
            let name: String?
            let bytes: Int
        }

        let packs: [Entry]
    }

    private struct Manifest: Decodable {
        struct Bounds: Decodable {
            let park: Corners
            let rendered: Corners
        }

        /// `[west, south, east, north]`.
        struct Corners: Decodable {
            let values: [Double]

            init(from decoder: any Decoder) throws {
                values = try decoder.singleValueContainer().decode([Double].self)
            }

            var box: BoundingBox? {
                guard values.count == 4 else { return nil }
                return BoundingBox(
                    south: values[1], west: values[0], north: values[3], east: values[2]
                )
            }
        }

        struct Tiles: Decodable {
            let file: String
            let minZoom: Int
            let maxZoom: Int
        }

        let name: String
        let bounds: Bounds
        let tiles: Tiles
    }
}

/// Reads tiles from an MBTiles file: SQLite, opened read-only and immutable, since a
/// bundled pack never changes. One connection, behind a lock, for MapKit's tile threads.
public final class MBTilesReader: Sendable {
    public enum Failure: Error {
        case cannotOpen(String)
    }

    private let connection: Mutex<OpaquePointer?>

    public init(url: URL) throws {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "file"
        components?.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        let uri = components?.string ?? url.absoluteString
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            sqlite3_close(handle)
            throw Failure.cannotOpen(message)
        }
        connection = Mutex(handle)
    }

    deinit {
        connection.withLock { handle in
            sqlite3_close(handle)
            handle = nil
        }
    }

    /// The tile at an XYZ address — its row counted from the north, as MapKit counts.
    /// MBTiles stores TMS rows, counted from the south, so the row is flipped here.
    public func tile(zoom: Int, column: Int, row fromNorth: Int) -> Data? {
        guard zoom >= 0, zoom < 31 else { return nil }
        let row = (1 << zoom) - 1 - fromNorth
        return connection.withLock { handle -> Data? in
            guard let handle else { return nil }
            var statement: OpaquePointer?
            let sql = "SELECT tile_data FROM tiles "
                + "WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1"
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(zoom))
            sqlite3_bind_int(statement, 2, Int32(column))
            sqlite3_bind_int(statement, 3, Int32(row))
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let blob = sqlite3_column_blob(statement, 0)
            else { return nil }
            // Copied out before the statement is finalised, which frees the blob.
            return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 0)))
        }
    }
}
