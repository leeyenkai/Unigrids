import Foundation
import UnigridsCore

public enum ReferenceStoreError: Error, CustomStringConvertible {
    case missingResource(String)
    case undecodable(resource: String, underlying: any Error)

    public var description: String {
        switch self {
        case let .missingResource(name):
            "Reference data is missing from the app bundle: \(name)"
        case let .undecodable(resource, underlying):
            "Reference data could not be decoded (\(resource)): \(underlying)"
        }
    }
}

/// The reference dataset as it ships inside the app.
///
/// Everything is decoded up front and held immutably, which makes the store a plain
/// `Sendable` value with no locking and no lazy-cache invalidation to get wrong. The whole
/// dataset is small enough for that today; when offline packs and 63 full guides make it
/// large, the thing to replace is the storage format (SQLite, as §3 and §13 intend), not
/// this interface.
public struct BundledReferenceStore: ReferenceStore {
    public let manifest: ReferenceManifest
    public let places: [Place]
    public let themes: [Theme]

    private let placesByID: [UnigridsID: Place]
    private let themesByID: [UnigridsID: Theme]
    private let poisByPlace: [UnigridsID: [PointOfInterest]]
    private let trailsByPlace: [UnigridsID: [Trail]]
    private let guidesByPlace: [UnigridsID: GuideContent]

    /// Load the dataset that ships with `UnigridsReference`.
    ///
    /// `Bundle.module` is internal to this module, so this is the entry point callers use
    /// rather than passing a bundle themselves.
    public static func bundled() throws -> BundledReferenceStore {
        try BundledReferenceStore(bundle: .module)
    }

    /// Load the dataset from an explicit bundle, for tests and for a host app that
    /// carries the resources itself.
    public init(bundle: Bundle) throws {
        let decoder = JSONDecoder()

        manifest = try Self.decode(ReferenceManifest.self, "manifest", bundle, decoder)
        places = try Self.decode([Place].self, "places", bundle, decoder)
        themes = try Self.decode([Theme].self, "themes", bundle, decoder)
        let pois = try Self.decode([PointOfInterest].self, "pois", bundle, decoder)
        // Trails are specified (§8) but not populated until 1.0.0, so an absent file is
        // the expected state rather than an error.
        let trails = try Self.decodeIfPresent([Trail].self, "trails", bundle, decoder) ?? []

        placesByID = Self.keyed(places, by: \.id)
        themesByID = Self.keyed(themes, by: \.id)
        poisByPlace = Dictionary(grouping: pois, by: \.placeID)
        trailsByPlace = Dictionary(grouping: trails, by: \.placeID)

        var guides: [UnigridsID: GuideContent] = [:]
        for place in places where place.tier.hasGuide {
            guard let guide = try Self.decodeIfPresent(
                GuideContent.self,
                "guides/\(place.id.rawValue)",
                bundle,
                decoder
            ) else { continue }
            guides[place.id] = guide
        }
        guidesByPlace = guides
    }

    private init(
        manifest: ReferenceManifest,
        places: [Place],
        themes: [Theme],
        pois: [PointOfInterest],
        trails: [Trail],
        guides: [GuideContent]
    ) {
        self.manifest = manifest
        self.places = places
        self.themes = themes
        placesByID = Self.keyed(places, by: \.id)
        themesByID = Self.keyed(themes, by: \.id)
        poisByPlace = Dictionary(grouping: pois, by: \.placeID)
        trailsByPlace = Dictionary(grouping: trails, by: \.placeID)
        guidesByPlace = Self.keyed(guides, by: \.placeID)
    }

    /// Index values by id, keeping the first of any duplicate.
    ///
    /// A duplicate id means the pipeline emitted a broken dataset. Dropping the later
    /// copy keeps the app usable; `BundledDataTests` is what catches the duplicate.
    private static func keyed<Value>(
        _ values: [Value],
        by key: (Value) -> UnigridsID
    ) -> [UnigridsID: Value] {
        Dictionary(values.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// An empty store, for previews and for the release-build fallback when bundled data
    /// cannot be read. The app shows an explicit "reference data unavailable" state rather
    /// than crashing in a user's hands.
    public static func empty(note: String? = nil) -> BundledReferenceStore {
        BundledReferenceStore(
            manifest: ReferenceManifest(
                version: 0,
                builtOn: "",
                provenance: .seed,
                note: note ?? "No reference data loaded."
            ),
            places: [],
            themes: [],
            pois: [],
            trails: [],
            guides: []
        )
    }

    /// A store built from values in memory, for previews and tests.
    public static func inMemory(
        places: [Place],
        pois: [PointOfInterest] = [],
        trails: [Trail] = [],
        themes: [Theme] = [],
        guides: [GuideContent] = []
    ) -> BundledReferenceStore {
        BundledReferenceStore(
            manifest: ReferenceManifest(
                version: 0,
                builtOn: "",
                provenance: .seed,
                note: "In-memory store."
            ),
            places: places,
            themes: themes,
            pois: pois,
            trails: trails,
            guides: guides
        )
    }

    public func place(_ id: UnigridsID) -> Place? {
        placesByID[id]
    }

    public func theme(_ id: UnigridsID) -> Theme? {
        themesByID[id]
    }

    public func pointsOfInterest(in placeID: UnigridsID) -> [PointOfInterest] {
        poisByPlace[placeID] ?? []
    }

    public func trails(in placeID: UnigridsID) -> [Trail] {
        trailsByPlace[placeID] ?? []
    }

    public func guide(for placeID: UnigridsID) -> GuideContent? {
        guidesByPlace[placeID]
    }

    // MARK: - Decoding

    private static func url(_ name: String, _ bundle: Bundle) -> URL? {
        // Resource names carry a subdirectory for guides, which `Bundle.url(forResource:)`
        // will not split for us.
        let parts = name.split(separator: "/")
        let file = String(parts.last ?? "")
        let subdirectory = (["reference"] + parts.dropLast().map(String.init))
            .joined(separator: "/")
        return bundle.url(forResource: file, withExtension: "json", subdirectory: subdirectory)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        _ name: String,
        _ bundle: Bundle,
        _ decoder: JSONDecoder
    ) throws -> T {
        guard let value = try decodeIfPresent(type, name, bundle, decoder) else {
            throw ReferenceStoreError.missingResource("\(name).json")
        }
        return value
    }

    private static func decodeIfPresent<T: Decodable>(
        _: T.Type,
        _ name: String,
        _ bundle: Bundle,
        _ decoder: JSONDecoder
    ) throws -> T? {
        guard let url = url(name, bundle) else { return nil }
        do {
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw ReferenceStoreError.undecodable(resource: "\(name).json", underlying: error)
        }
    }
}
