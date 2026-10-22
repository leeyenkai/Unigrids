import Foundation

public enum TrailDifficulty: String, CaseIterable, Sendable, Codable, Comparable {
    case easy
    case moderate
    case moderatelyStrenuous
    case strenuous
    case veryStrenuous

    public var name: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .moderatelyStrenuous: "Moderately strenuous"
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

    /// An estimate from length and climb, by the rating Shenandoah National Park
    /// publishes for its own trails: the square root of (gain in feet × 2 × miles), read
    /// against fixed bands — under 50 easiest, then every 50 a step harder, and over 200
    /// very strenuous.
    ///
    /// A formula, not a ranger's judgement: it knows nothing of exposure, scrambling or
    /// heat, and the app labels it an estimate wherever it shows it.
    public static func estimate(lengthMetres: Double, gainMetres: Double) -> TrailDifficulty {
        let feet = max(gainMetres, 0) * 3.280_84
        let miles = max(lengthMetres, 0) / 1609.344
        let rating = (feet * 2 * miles).squareRoot()
        switch rating {
        case ..<50: return .easy
        case ..<100: return .moderate
        case ..<150: return .moderatelyStrenuous
        case ..<200: return .strenuous
        default: return .veryStrenuous
        }
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

/// A named trail feature, used by the catalogue's filters. Read from the trail's own name
/// by the pipeline, so "Lake Trail" is a lake and a trail that passes one unnamed is not.
public enum TrailFeature: String, CaseIterable, Sendable, Codable, Identifiable {
    case waterfall, summit, lake, arch, beach, canyon, forest, meadow, glacier, cave

    public var id: String {
        rawValue
    }

    public var name: String {
        rawValue.capitalized
    }
}

/// One point of a trail's elevation profile.
public struct TrailProfilePoint: Hashable, Sendable {
    public let distanceMetres: Double
    public let elevationMetres: Double

    public init(distanceMetres: Double, elevationMetres: Double) {
        self.distanceMetres = distanceMetres
        self.elevationMetres = elevationMetres
    }
}

/// A trail in the catalogue (SPECIFICATION.md §8, §13).
///
/// Length, elevation and the profile are computed by the pipeline from the route line and
/// USGS elevation data, so every trail is measured the same way and the numbers do not
/// depend on who published the source. A trail the elevation service could not cover
/// carries its length and no climb: an absent figure, not a zero.
public struct Trail: Identifiable, Hashable, Sendable {
    public let id: UnigridsID
    public let placeID: UnigridsID
    public let name: String
    /// Horizontal length of the line as mapped: one way, or once round a loop. A hike's
    /// distance is `walkedMetres`.
    public let lengthMetres: Double
    public let gainMetres: Double?
    public let lossMetres: Double?
    public let lowPointMetres: Double?
    public let highPointMetres: Double?
    /// A difficulty a source published. The NPS trails layer publishes none, so the
    /// catalogue leans on `estimatedDifficulty`.
    public let difficulty: TrailDifficulty?
    /// Only a loop can be read off a line; anything else is left unsaid.
    public let routeType: RouteType?
    public let trailheadID: UnigridsID?
    public let features: [TrailFeature]
    /// Sights passed along the way, in walking order.
    public let sightIDs: [UnigridsID]
    public let seasonalNotes: String?
    public let dogsAllowed: Bool?
    public let bikesAllowed: Bool?
    /// Permitted uses as the park's GIS staff recorded them: "Hiker/Pedestrian, Bicycle".
    public let uses: String?
    /// The line, in one or more parts.
    public let paths: [[Coordinate]]
    /// Elevation along the whole trail, its parts laid end to end in walking order.
    public let profile: [TrailProfilePoint]
    /// Where the line came from when it is not the park's own: `"osm"` for trails taken
    /// from OpenStreetMap, which the trail's page credits under the ODbL.
    public let source: String?

    /// Whether the line is OpenStreetMap's rather than the NPS's.
    public var isFromOpenStreetMap: Bool {
        source == "osm"
    }

    /// Whether the line closes on itself, and so is walked once round.
    public var isLoop: Bool {
        routeType == .loop
    }

    /// The distance a hike of the trail covers: once round a loop, there and back along
    /// anything else. Most park trails are walked out and back, and the line as mapped
    /// runs one way — Bright Angel is digitised rim to river, so measured one way it barely
    /// climbs. A point-to-point trail, where the data says so, is walked once.
    public var walkedMetres: Double {
        routeType == .outAndBack || routeType == nil ? lengthMetres * 2 : lengthMetres
    }

    /// The climbing a hike of the trail involves, by the same rule: the rise round a loop,
    /// or the rise one way plus the rise back (which is the fall one way).
    public var climbMetres: Double? {
        guard let gainMetres else { return nil }
        return routeType == .outAndBack || routeType == nil
            ? gainMetres + (lossMetres ?? 0) : gainMetres
    }

    /// The published difficulty, or the estimate from the hike's distance and climb.
    public var estimatedDifficulty: TrailDifficulty? {
        if let difficulty {
            return difficulty
        }
        guard let climbMetres else { return nil }
        return TrailDifficulty.estimate(lengthMetres: walkedMetres, gainMetres: climbMetres)
    }

    /// Naismith's rule: 5 km/h on the flat, plus an hour for every 600 m of ascent, for
    /// the hike as `walkedMetres` describes it. A planning estimate, not a promise.
    public var estimatedDuration: TimeInterval {
        let flat = walkedMetres / 1000 / 5 * 3600
        let climb = (climbMetres ?? 0) / 600 * 3600
        return flat + climb
    }

    /// Whether the trail's climb was measured.
    public var isMeasured: Bool {
        gainMetres != nil
    }

    /// The box around the line, for framing it on a map.
    public var extent: BoundingBox? {
        BoundingBox.enclosing(paths.flatMap(\.self))
    }

    /// Where the trail starts, as mapped.
    public var start: Coordinate? {
        paths.first?.first
    }

    public init(
        id: UnigridsID,
        placeID: UnigridsID,
        name: String,
        lengthMetres: Double,
        gainMetres: Double? = nil,
        lossMetres: Double? = nil,
        lowPointMetres: Double? = nil,
        highPointMetres: Double? = nil,
        difficulty: TrailDifficulty? = nil,
        routeType: RouteType? = nil,
        trailheadID: UnigridsID? = nil,
        features: [TrailFeature] = [],
        sightIDs: [UnigridsID] = [],
        seasonalNotes: String? = nil,
        dogsAllowed: Bool? = nil,
        bikesAllowed: Bool? = nil,
        uses: String? = nil,
        paths: [[Coordinate]] = [],
        profile: [TrailProfilePoint] = [],
        source: String? = nil
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
        self.uses = uses
        self.paths = paths
        self.profile = profile
        self.source = source
    }
}

extension Trail: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, placeID, name, lengthMetres, gainMetres, lossMetres, lowPointMetres
        case highPointMetres, difficulty, routeType, trailheadID, features, sightIDs
        case seasonalNotes, dogsAllowed, bikesAllowed, uses, paths, profile, source
    }

    /// Paths are encoded polylines; the profile is `[[distance, elevation], …]`. Unknown
    /// feature names from a newer dataset are dropped rather than failing the trail.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
        let profile = try container.decodeIfPresent([[Double]].self, forKey: .profile) ?? []
        let paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        try self.init(
            id: container.decode(UnigridsID.self, forKey: .id),
            placeID: container.decode(UnigridsID.self, forKey: .placeID),
            name: container.decode(String.self, forKey: .name),
            lengthMetres: container.decode(Double.self, forKey: .lengthMetres),
            gainMetres: container.decodeIfPresent(Double.self, forKey: .gainMetres),
            lossMetres: container.decodeIfPresent(Double.self, forKey: .lossMetres),
            lowPointMetres: container.decodeIfPresent(Double.self, forKey: .lowPointMetres),
            highPointMetres: container.decodeIfPresent(Double.self, forKey: .highPointMetres),
            difficulty: try? container.decodeIfPresent(TrailDifficulty.self, forKey: .difficulty),
            routeType: try? container.decodeIfPresent(RouteType.self, forKey: .routeType),
            trailheadID: container.decodeIfPresent(UnigridsID.self, forKey: .trailheadID),
            features: features.compactMap(TrailFeature.init(rawValue:)),
            sightIDs: container.decodeIfPresent([UnigridsID].self, forKey: .sightIDs) ?? [],
            seasonalNotes: container.decodeIfPresent(String.self, forKey: .seasonalNotes),
            dogsAllowed: container.decodeIfPresent(Bool.self, forKey: .dogsAllowed),
            bikesAllowed: container.decodeIfPresent(Bool.self, forKey: .bikesAllowed),
            uses: container.decodeIfPresent(String.self, forKey: .uses),
            paths: paths.map(Polyline.decode).filter { $0.count >= 2 },
            profile: profile.compactMap { pair in
                pair.count == 2
                    ? TrailProfilePoint(distanceMetres: pair[0], elevationMetres: pair[1])
                    : nil
            },
            source: container.decodeIfPresent(String.self, forKey: .source)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(placeID, forKey: .placeID)
        try container.encode(name, forKey: .name)
        try container.encode(lengthMetres, forKey: .lengthMetres)
        try container.encodeIfPresent(gainMetres, forKey: .gainMetres)
        try container.encodeIfPresent(lossMetres, forKey: .lossMetres)
        try container.encodeIfPresent(lowPointMetres, forKey: .lowPointMetres)
        try container.encodeIfPresent(highPointMetres, forKey: .highPointMetres)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encodeIfPresent(routeType, forKey: .routeType)
        try container.encodeIfPresent(trailheadID, forKey: .trailheadID)
        try container.encode(features.map(\.rawValue), forKey: .features)
        try container.encode(sightIDs, forKey: .sightIDs)
        try container.encodeIfPresent(seasonalNotes, forKey: .seasonalNotes)
        try container.encodeIfPresent(dogsAllowed, forKey: .dogsAllowed)
        try container.encodeIfPresent(bikesAllowed, forKey: .bikesAllowed)
        try container.encodeIfPresent(uses, forKey: .uses)
        try container.encode(paths.map(Polyline.encode), forKey: .paths)
        try container.encode(
            profile.map { [$0.distanceMetres, $0.elevationMetres] }, forKey: .profile
        )
        try container.encodeIfPresent(source, forKey: .source)
    }
}

extension UnigridsFormat {
    /// How far a hike of a trail goes, saying which way it was measured: "5 km loop",
    /// "12.7 km one way" where the data says it ends elsewhere, or, for the usual trail
    /// mapped one way, "12.7 km one way · 25.4 km there and back".
    public static func trailLength(_ trail: Trail, locale: Locale = .current) -> String {
        let oneWay = distance(metres: trail.lengthMetres, locale: locale)
        switch trail.routeType {
        case .loop:
            return oneWay + " loop"
        case .pointToPoint:
            return oneWay + " one way"
        case .outAndBack, nil:
            let both = distance(metres: trail.walkedMetres, locale: locale)
            return oneWay + " one way · " + both + " there and back"
        }
    }
}
