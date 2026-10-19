import Foundation

/// Which places the map shows (SPECIFICATION.md §5, "Filters").
///
/// A value rather than a set of view toggles so the rule — what a filter combination
/// actually lets through — is testable, and so the map, the legend and the filter sheet
/// read one definition.
public struct MapFilter: Hashable, Sendable, Codable {
    /// Whether to narrow by the reader's own log.
    public enum Visits: String, CaseIterable, Sendable, Codable, Identifiable {
        case all
        case visited
        case notVisited

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .all: "All places"
            case .visited: "Visited"
            case .notVisited: "Not yet visited"
            }
        }
    }

    public var tiers: Set<PlaceTier>
    public var visits: Visits

    public init(tiers: Set<PlaceTier> = Set(PlaceTier.allCases), visits: Visits = .all) {
        self.tiers = tiers
        self.visits = visits
    }

    /// Everything, which is where the map starts.
    public static let everything = MapFilter()

    /// Whether the filter has narrowed anything, for the toolbar's filled-or-not icon.
    public var isNarrowed: Bool {
        self != .everything
    }

    public func includes(_ place: Place, isVisited: Bool) -> Bool {
        guard tiers.contains(place.tier) else { return false }
        switch visits {
        case .all: return true
        case .visited: return isVisited
        case .notVisited: return !isVisited
        }
    }
}

extension PlaceTier {
    /// The tier's name in the map legend and filters.
    public var name: String {
        switch self {
        case .nationalPark: "National parks"
        case .npsUnit: "Other NPS sites"
        case .statePark: "State parks"
        case .federalSite: "Monuments and refuges"
        }
    }

    /// One line on what the tier covers, for the filter sheet.
    public var detail: String {
        switch self {
        case .nationalPark: "All 63, each with a full guide"
        case .npsUnit: "Monuments, historic sites, seashores, memorials and more"
        case .statePark: "A selection of well-known state parks"
        case .federalSite: "BLM and Forest Service monuments, and wildlife refuges"
        }
    }
}

/// How much the map draws at a given zoom.
///
/// Four hundred outlines at country scale are a smear and a cost; one tier's outlines at
/// regional scale are the point. The thresholds are latitude spans in degrees, the same
/// figure MapKit reports for the visible region.
public enum MapDetail {
    /// Below this span, outlines for every tier are drawn. Above it, only national parks.
    public static let allOutlinesSpan: Double = 14

    /// Whether a tier's outlines are drawn at a latitude span.
    public static func showsOutline(for tier: PlaceTier, latitudeSpan: Double) -> Bool {
        tier == .nationalPark || latitudeSpan <= allOutlinesSpan
    }

    /// Whether a place's name is worth printing beside its pin at a latitude span. National
    /// parks are labelled from regional zoom; everything else only once the map is close.
    public static func showsLabel(for tier: PlaceTier, latitudeSpan: Double) -> Bool {
        switch tier {
        case .nationalPark: latitudeSpan <= 22
        case .npsUnit, .statePark, .federalSite: latitudeSpan <= 4
        }
    }
}
