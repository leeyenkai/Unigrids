import Foundation

public enum TrailDifficulty: String, CaseIterable, Sendable, Codable, Comparable {
    case easy
    case moderate
    case strenuous
    case veryStrenuous

    public var name: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .strenuous: "Strenuous"
        case .veryStrenuous: "Very strenuous"
        }
    }

    public static func < (lhs: TrailDifficulty, rhs: TrailDifficulty) -> Bool {
        guard let left = allCases.firstIndex(of: lhs),
              let right = allCases.firstIndex(of: rhs)
        else { return false }
        return left < right
    }
}

public enum RouteType: String, CaseIterable, Sendable, Codable {
    case loop
    case outAndBack
    case pointToPoint

    public var name: String {
        switch self {
        case .loop: "Loop"
        case .outAndBack: "Out and back"
        case .pointToPoint: "Point to point"
        }
    }
}

/// A named trail feature, used by the catalogue's filters.
public enum TrailFeature: String, CaseIterable, Sendable, Codable, Identifiable {
    case waterfall, summit, lake, arch, beach, canyon, forest, meadow, glacier, cave

    public var id: String {
        rawValue
    }

    public var name: String {
        rawValue.capitalized
    }
}

/// A trail in the catalogue (SPECIFICATION.md §8, §13).
///
/// Length, elevation and the profile are computed by the pipeline from the route line and
/// USGS elevation data, so every trail is measured the same way and the numbers do not
/// depend on who published the source.
///
/// Not populated in the 0.1.0 pilot: the type exists so the model, the log and the stats
/// are shaped for it, but the catalogue needs the NPS Public Trails dataset first.
/// See `docs/mvp-scope.md`.
public struct Trail: Identifiable, Hashable, Sendable, Codable {
    public let id: UnigridsID
    public let placeID: UnigridsID
    public let name: String
    public let lengthMetres: Double
    public let gainMetres: Double
    public let lossMetres: Double
    public let lowPointMetres: Double?
    public let highPointMetres: Double?
    public let difficulty: TrailDifficulty
    public let routeType: RouteType
    public let trailheadID: UnigridsID?
    public let features: [TrailFeature]
    /// Sights passed along the way, in walking order.
    public let sightIDs: [UnigridsID]
    public let seasonalNotes: String?
    public let dogsAllowed: Bool?
    public let bikesAllowed: Bool?

    /// Naismith's rule with Langmuir's descent correction: 5 km/h on the flat, plus an
    /// hour for every 600 m of ascent. A planning estimate, not a promise.
    public var estimatedDuration: TimeInterval {
        let flat = lengthMetres / 1000 / 5 * 3600
        let climb = gainMetres / 600 * 3600
        return flat + climb
    }

    public init(
        id: UnigridsID,
        placeID: UnigridsID,
        name: String,
        lengthMetres: Double,
        gainMetres: Double,
        lossMetres: Double,
        lowPointMetres: Double? = nil,
        highPointMetres: Double? = nil,
        difficulty: TrailDifficulty,
        routeType: RouteType,
        trailheadID: UnigridsID? = nil,
        features: [TrailFeature] = [],
        sightIDs: [UnigridsID] = [],
        seasonalNotes: String? = nil,
        dogsAllowed: Bool? = nil,
        bikesAllowed: Bool? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.name = name
        self.lengthMetres = lengthMetres
        self.gainMetres = gainMetres
        self.lossMetres = lossMetres
        self.lowPointMetres = lowPointMetres
        self.highPointMetres = highPointMetres
        self.difficulty = difficulty
        self.routeType = routeType
        self.trailheadID = trailheadID
        self.features = features
        self.sightIDs = sightIDs
        self.seasonalNotes = seasonalNotes
        self.dogsAllowed = dogsAllowed
        self.bikesAllowed = bikesAllowed
    }
}
