import Foundation

/// What a point of interest is, which fixes its icon and where it appears.
public enum POIKind: String, CaseIterable, Sendable, Codable {
    case sight
    case visitorCentre
    case viewpoint
    case entrance
    case trailhead
    case stampLocation
    case campground

    public var name: String {
        switch self {
        case .sight: "Sight"
        case .visitorCentre: "Visitor centre"
        case .viewpoint: "Viewpoint"
        case .entrance: "Entrance"
        case .trailhead: "Trailhead"
        case .stampLocation: "Stamp location"
        case .campground: "Campground"
        }
    }

    /// Whether a user can check in here. Entrances are waypoints, not destinations.
    public var isCheckInTarget: Bool {
        self != .entrance
    }
}

/// A point inside a place: a sight, visitor centre, viewpoint, entrance, trailhead or
/// stamp location (SPECIFICATION.md §13).
///
/// Reference data. Sights carry a `rank` so the guide's "Major sights" panel, the 3D
/// view's numbered pins and the fly-through all agree on the order.
public struct PointOfInterest: Identifiable, Hashable, Sendable, Codable {
    public let id: UnigridsID
    public let placeID: UnigridsID
    public let kind: POIKind
    public let name: String
    public let location: Coordinate
    /// Lower sorts first. Sights are ranked by the pipeline; everything else may share 0.
    public let rank: Int
    public let summary: String?
    /// Opening hours as published, free text, because NPS publishes them that way.
    public let hours: String?
    /// Services at a visitor centre: bookshop, exhibits, film, permits.
    public let services: [String]
    /// Whether this is an official passport cancellation location.
    public let hasStamp: Bool
    /// A photograph of it, credited.
    public let image: GuideImage?
    /// Its own page on the NPS site, where it has one.
    public let url: URL?

    public init(
        id: UnigridsID,
        placeID: UnigridsID,
        kind: POIKind,
        name: String,
        location: Coordinate,
        rank: Int = 0,
        summary: String? = nil,
        hours: String? = nil,
        services: [String] = [],
        hasStamp: Bool = false,
        image: GuideImage? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.kind = kind
        self.name = name
        self.location = location
        self.rank = rank
        self.summary = summary
        self.hours = hours
        self.services = services
        self.hasStamp = hasStamp
        self.image = image
        self.url = url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UnigridsID.self, forKey: .id)
        placeID = try container.decode(UnigridsID.self, forKey: .placeID)
        kind = try container.decode(POIKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        location = try container.decode(Coordinate.self, forKey: .location)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        hours = try container.decodeIfPresent(String.self, forKey: .hours)
        services = try container.decodeIfPresent([String].self, forKey: .services) ?? []
        hasStamp = try container.decodeIfPresent(Bool.self, forKey: .hasStamp)
            ?? (kind == .stampLocation)
        image = try container.decodeIfPresent(GuideImage.self, forKey: .image)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
    }
}
