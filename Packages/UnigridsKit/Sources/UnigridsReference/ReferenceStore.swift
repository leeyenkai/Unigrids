import Foundation
import UnigridsCore

/// What the reference dataset says about itself.
///
/// The pipeline writes this on every build so the app can show which dataset it shipped
/// with, and so a bug report names a dataset rather than an app version.
public struct ReferenceManifest: Hashable, Sendable, Codable {
    /// Dataset version, bumped by the pipeline's build step.
    public let version: Int
    /// When the pipeline built it.
    public let builtOn: String
    /// `pipeline` for generated data, `seed` for the hand-authored pilot set.
    public let provenance: Provenance
    /// Free-text note shown on the Settings data screen.
    public let note: String?

    public enum Provenance: String, Sendable, Codable {
        case pipeline
        case seed

        public var name: String {
            switch self {
            case .pipeline: "Built by the pipeline"
            case .seed: "Hand-authored pilot seed"
            }
        }
    }
}

/// Read-only access to the reference dataset.
///
/// A protocol rather than a concrete type so previews and tests can supply a handful of
/// places without touching the bundle. Nothing here mutates: the pipeline replaces the
/// dataset wholesale with each app release (`docs/adr/0002`).
public protocol ReferenceStore: Sendable {
    var manifest: ReferenceManifest { get }

    /// Every place in the dataset, in no guaranteed order.
    var places: [Place] { get }

    /// Every theme tag.
    var themes: [Theme] { get }

    func place(_ id: UnigridsID) -> Place?
    func theme(_ id: UnigridsID) -> Theme?
    func pointsOfInterest(in placeID: UnigridsID) -> [PointOfInterest]
    func trails(in placeID: UnigridsID) -> [Trail]
    /// Every trail in the catalogue, across every park.
    var allTrails: [Trail] { get }
    func guide(for placeID: UnigridsID) -> GuideContent?

    /// A place's outline, where the dataset carries one.
    func boundary(for placeID: UnigridsID) -> PlaceBoundary?

    /// Every outline, for the map to draw.
    var boundaries: [UnigridsID: PlaceBoundary] { get }

    /// A place's official brochure and maps, where the NPS publishes any.
    func documents(for placeID: UnigridsID) -> ParkDocuments?

    /// A national park's monthly climate.
    func climate(for placeID: UnigridsID) -> MonthlyClimate?

    /// Every outline again, generalised for the map at country scale. A place missing here
    /// is too small to see from that far out.
    var overviewBoundaries: [UnigridsID: PlaceBoundary] { get }

    /// Every line-shaped place's route — the scenic byways — for the map to draw.
    var routes: [UnigridsID: RouteLine] { get }

    /// Places with at least one official passport stamp location.
    var placesWithStampLocations: Set<UnigridsID> { get }

    /// The road and rail layers. Read on demand rather than at launch, because nobody
    /// needs four thousand kilometres of Interstate to open the app.
    func transportNetwork() throws -> TransportNetwork

    /// Where an image's bytes are: a file inside the app for a bundled photograph, the
    /// remote URL otherwise.
    func imageURL(for image: GuideImage) -> URL?
}

extension ReferenceStore {
    /// The 63 national parks, by name.
    public var nationalParks: [Place] {
        places
            .filter { $0.tier == .nationalPark }
            .sorted { $0.name < $1.name }
    }

    /// Sights in a place, in the order the guide and the 3D view both use.
    public func sights(in placeID: UnigridsID) -> [PointOfInterest] {
        pointsOfInterest(in: placeID)
            .filter { $0.kind == .sight || $0.kind == .viewpoint }
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    public func visitorCentres(in placeID: UnigridsID) -> [PointOfInterest] {
        pointsOfInterest(in: placeID)
            .filter { $0.kind == .visitorCentre }
            .sorted { $0.name < $1.name }
    }

    /// Official passport cancellation locations in a place.
    ///
    /// A site with several of these gets one passport slot per location (§9).
    public func stampLocations(in placeID: UnigridsID) -> [PointOfInterest] {
        pointsOfInterest(in: placeID)
            .filter(\.hasStamp)
            .sorted { $0.name < $1.name }
    }

    /// Places matching a free-text query across name, designation and state.
    public func search(_ query: String, limit: Int = 50) -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        return places
            .compactMap { place -> (Place, Int)? in
                guard let score = place.matchScore(for: needle) else { return nil }
                return (place, score)
            }
            // Equal matches put the deepest places first: a national park before the
            // forest and the landmark that share its name or its state.
            .sorted {
                ($0.1, $0.0.tier.rawValue, $0.0.name) < ($1.1, $1.0.tier.rawValue, $1.0.name)
            }
            .prefix(limit)
            .map(\.0)
    }

    /// The places nearest a coordinate, nearest first. A place whose outline holds the
    /// point is nearest of all, however far its centre is: standing in a park, the park
    /// is where you are.
    public func nearest(
        to coordinate: Coordinate,
        limit: Int = 5,
        tiers: Set<PlaceTier> = Set(PlaceTier.allCases)
    ) -> [Place] {
        places
            .filter { tiers.contains($0.tier) }
            .map { place in
                let inside = boundary(for: place.id)?.contains(coordinate) == true
                return (place, inside ? 0 : coordinate.distance(to: place.centre))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Every place in a tier, by name.
    public func places(in tier: PlaceTier) -> [Place] {
        places
            .filter { $0.tier == tier }
            .sorted { $0.name < $1.name }
    }

    /// The place whose outline holds a point — the smallest, where outlines overlap, since
    /// a tap inside a state park inside a national forest means the state park.
    ///
    /// `candidates` narrows the search to what the map is actually showing.
    public func place(at point: Coordinate, among candidates: [Place]? = nil) -> Place? {
        (candidates ?? places)
            .compactMap { place -> (Place, Double)? in
                guard let boundary = boundary(for: place.id), boundary.contains(point)
                else { return nil }
                return (place, boundary.extent.degreeArea)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// The box to frame a place in: its outline's, else its curated extent, else a small
    /// box around its centre.
    public func frame(for place: Place) -> BoundingBox {
        if let extent = boundary(for: place.id)?.extent {
            return extent
        }
        if let extent = place.extent {
            return extent
        }
        let pad = 0.15
        return BoundingBox(
            south: place.centre.latitude - pad,
            west: place.centre.longitude - pad,
            north: place.centre.latitude + pad,
            east: place.centre.longitude + pad
        )
    }

    /// Points of interest across every place, matching a query, for map search.
    public func searchPointsOfInterest(_ query: String, limit: Int = 20) -> [PointOfInterest] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return [] }
        return places
            .filter(\.tier.hasGuide)
            .flatMap { pointsOfInterest(in: $0.id) }
            .filter { $0.kind != .entrance && $0.name.lowercased().contains(needle) }
            .sorted { ($0.name.lowercased().hasPrefix(needle) ? 0 : 1, $0.name)
                < ($1.name.lowercased().hasPrefix(needle) ? 0 : 1, $1.name)
            }
            .prefix(limit)
            .map(\.self)
    }

    /// A byway's line, where the place is one.
    public func route(for placeID: UnigridsID) -> RouteLine? {
        routes[placeID]
    }

    /// Places of one site type, by name.
    public func places(of type: SiteType) -> [Place] {
        places
            .filter { $0.siteType == type }
            .sorted { $0.name < $1.name }
    }

    /// Places grouped by the region they stamp in, for the passport's section pages.
    public func placesByPassportRegion() -> [PassportRegion: [Place]] {
        Dictionary(grouping: places, by: \.resolvedPassportRegion)
            .mapValues { $0.sorted { $0.name < $1.name } }
    }
}

extension Place {
    /// Lower is a better match. `nil` means no match at all.
    fileprivate func matchScore(for needle: String) -> Int? {
        let name = name.lowercased()
        if name.hasPrefix(needle) {
            return 0
        }
        if name.contains(needle) {
            return 1
        }
        // Two letters that are a state's code mean the state: "UT" is Utah.
        if needle.count == 2, states.contains(where: { $0.code.lowercased() == needle }) {
            return 1
        }
        if designation.lowercased().contains(needle) {
            return 2
        }
        if states.contains(where: {
            $0.name.lowercased().hasPrefix(needle) || $0.code.lowercased() == needle
        }) {
            return 3
        }
        if let code = npsParkCode?.lowercased(), code == needle {
            return 0
        }
        return nil
    }
}
