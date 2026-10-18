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
    func guide(for placeID: UnigridsID) -> GuideContent?
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
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .prefix(limit)
            .map(\.0)
    }

    /// The places nearest a coordinate, nearest first.
    public func nearest(to coordinate: Coordinate, limit: Int = 5) -> [Place] {
        places
            .map { ($0, coordinate.distance(to: $0.centre)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
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
