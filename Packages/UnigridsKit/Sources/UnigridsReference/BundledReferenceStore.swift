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
    private let trailCatalogue: LazyTrails
    private let guidesByPlace: [UnigridsID: GuideContent]
    private let boundariesByPlace: [UnigridsID: PlaceBoundary]
    private let routesByPlace: [UnigridsID: RouteLine]
    private let documentsByPlace: [UnigridsID: ParkDocuments]
    private let climateByPlace: [UnigridsID: MonthlyClimate]
    public let overviewBoundaries: [UnigridsID: PlaceBoundary]
    public let placesWithStampLocations: Set<UnigridsID>
    /// Where the dataset's files are, for what is read on demand; `nil` in memory.
    private let referenceBundle: Bundle?
    /// Where bundled photographs live, or `nil` for a store built in memory.
    private let imageDirectory: URL?

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
        // The trail catalogue is decoded the first time anything asks for a trail: it is
        // the largest file, and the map the app opens on needs none of it.
        trailCatalogue = LazyTrails(url: Self.url("trails", bundle))
        // Outlines arrived with the pipeline's reference build. A dataset without them is
        // older, not broken: the map draws pins and no outlines.
        boundariesByPlace = try Self.decodeIfPresent(
            [String: PlaceBoundary].self, "boundaries", bundle, decoder
        )
        .map { Dictionary(uniqueKeysWithValues: $0.map { (UnigridsID($0.key), $0.value) }) }
        ?? [:]
        overviewBoundaries = try Self.decodeIfPresent(
            [String: PlaceBoundary].self, "boundaries-overview", bundle, decoder
        )
        .map { Dictionary(uniqueKeysWithValues: $0.map { (UnigridsID($0.key), $0.value) }) }
        ?? [:]
        // Byway lines arrived with the other public lands; an older dataset has none.
        routesByPlace = try Self.decodeIfPresent(
            [String: RouteLine].self, "routes", bundle, decoder
        )
        .map { Dictionary(uniqueKeysWithValues: $0.map { (UnigridsID($0.key), $0.value) }) }
        ?? [:]
        documentsByPlace = try Self.decodeIfPresent(
            [String: ParkDocuments].self, "brochures", bundle, decoder
        )
        .map { Dictionary(uniqueKeysWithValues: $0.map { (UnigridsID($0.key), $0.value) }) }
        ?? [:]
        climateByPlace = try Self.decodeIfPresent(
            [String: MonthlyClimate].self, "climate", bundle, decoder
        )
        .map { Dictionary(uniqueKeysWithValues: $0.map { (UnigridsID($0.key), $0.value) }) }
        ?? [:]
        referenceBundle = bundle
        imageDirectory = bundle.url(
            forResource: "images",
            withExtension: nil,
            subdirectory: "reference"
        )

        placesByID = Self.keyed(places, by: \.id)
        themesByID = Self.keyed(themes, by: \.id)
        poisByPlace = Dictionary(grouping: pois, by: \.placeID)
        placesWithStampLocations = Set(pois.filter(\.hasStamp).map(\.placeID))

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
        guides: [GuideContent],
        boundaries: [UnigridsID: PlaceBoundary] = [:],
        routes: [UnigridsID: RouteLine] = [:]
    ) {
        self.manifest = manifest
        self.places = places
        self.themes = themes
        placesByID = Self.keyed(places, by: \.id)
        themesByID = Self.keyed(themes, by: \.id)
        poisByPlace = Dictionary(grouping: pois, by: \.placeID)
        trailCatalogue = LazyTrails(trails: trails)
        guidesByPlace = Self.keyed(guides, by: \.placeID)
        boundariesByPlace = boundaries
        overviewBoundaries = boundaries
        routesByPlace = routes
        documentsByPlace = [:]
        climateByPlace = [:]
        placesWithStampLocations = Set(pois.filter(\.hasStamp).map(\.placeID))
        referenceBundle = nil
        imageDirectory = nil
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
        guides: [GuideContent] = [],
        boundaries: [UnigridsID: PlaceBoundary] = [:],
        routes: [UnigridsID: RouteLine] = [:]
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
            guides: guides,
            boundaries: boundaries,
            routes: routes
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
        trailCatalogue.value.byPlace[placeID] ?? []
    }

    public var allTrails: [Trail] {
        trailCatalogue.value.all
    }

    public func guide(for placeID: UnigridsID) -> GuideContent? {
        guidesByPlace[placeID]
    }

    public func boundary(for placeID: UnigridsID) -> PlaceBoundary? {
        boundariesByPlace[placeID]
    }

    /// Every outline, for the map to draw.
    public var boundaries: [UnigridsID: PlaceBoundary] {
        boundariesByPlace
    }

    public var routes: [UnigridsID: RouteLine] {
        routesByPlace
    }

    public func documents(for placeID: UnigridsID) -> ParkDocuments? {
        documentsByPlace[placeID]
    }

    public func climate(for placeID: UnigridsID) -> MonthlyClimate? {
        climateByPlace[placeID]
    }

    /// The road and rail layers, decoded from the bundle each time they are asked for.
    /// The map asks once, off the main actor, and keeps the answer.
    public func transportNetwork() throws -> TransportNetwork {
        guard let referenceBundle else { return .empty }
        return try Self.decodeIfPresent(
            TransportNetwork.self, "transport", referenceBundle, JSONDecoder()
        ) ?? .empty
    }

    public func imageURL(for image: GuideImage) -> URL? {
        if let assetName = image.assetName, let imageDirectory {
            let file = imageDirectory.appendingPathComponent(assetName)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return image.url
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

/// The trail catalogue, decoded on first use and kept.
///
/// A lock rather than an actor, because the store's API is synchronous and the decode
/// happens once. A catalogue that fails to decode is an empty one — the parks keep their
/// guides — and `BundledDataTests` is what notices.
final class LazyTrails: @unchecked Sendable {
    struct Catalogue {
        let all: [Trail]
        let byPlace: [UnigridsID: [Trail]]
    }

    private let lock = NSLock()
    private let url: URL?
    private var loaded: Catalogue?

    init(url: URL?) {
        self.url = url
    }

    init(trails: [Trail]) {
        url = nil
        loaded = Catalogue(all: trails, byPlace: Dictionary(grouping: trails, by: \.placeID))
    }

    var value: Catalogue {
        lock.withLock {
            if let loaded {
                return loaded
            }
            let trails = url
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([Trail].self, from: $0) } ?? []
            let catalogue = Catalogue(
                all: trails,
                byPlace: Dictionary(grouping: trails, by: \.placeID)
            )
            loaded = catalogue
            return catalogue
        }
    }
}
