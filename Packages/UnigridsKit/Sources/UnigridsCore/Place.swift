import Foundation

/// How much depth a place gets in the app (SPECIFICATION.md §5).
///
/// The tiers are the spine of the product: tier 1 earns a full Unigrid guide, 3D and
/// trails, and each tier below gets progressively less. Depth before breadth.
public enum PlaceTier: Int, CaseIterable, Sendable, Codable, Comparable {
    /// National parks. Full guide, brochure, 3D view, trail catalogue, offline pack.
    case nationalPark = 1
    /// Other NPS units. Rich pin: overview, hours, fees, alerts, brochure.
    case npsUnit = 2
    /// State parks. Pin and boundary, type, basic facts, link out.
    case statePark = 3
    /// Major federal sites. Pin or line, boundary, agency, basic facts.
    case federalSite = 4

    public static func < (lhs: PlaceTier, rhs: PlaceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var hasGuide: Bool {
        self == .nationalPark
    }
}

/// The land-management agency behind a place, which drives pin colour.
public enum Agency: String, CaseIterable, Sendable, Codable {
    case nps
    case forestService
    case blm
    case fishAndWildlife
    case stateAgency
    case other

    public var shortName: String {
        switch self {
        case .nps: "NPS"
        case .forestService: "USFS"
        case .blm: "BLM"
        case .fishAndWildlife: "USFWS"
        case .stateAgency: "State"
        case .other: "Other"
        }
    }

    public var name: String {
        switch self {
        case .nps: "National Park Service"
        case .forestService: "US Forest Service"
        case .blm: "Bureau of Land Management"
        case .fishAndWildlife: "US Fish and Wildlife Service"
        case .stateAgency: "State park agency"
        case .other: "Other"
        }
    }
}

/// What kind of place this is, which fixes its tier and its pin shape.
public enum PlaceKind: String, CaseIterable, Sendable, Codable {
    case nationalPark
    case npsUnit
    case statePark
    case nationalForest
    case nationalGrassland
    case blmMonument
    case blmConservationArea
    case wildlifeRefuge
    case naturalLandmark
    case scenicByway

    public var tier: PlaceTier {
        switch self {
        case .nationalPark: .nationalPark
        case .npsUnit: .npsUnit
        case .statePark: .statePark
        case .nationalForest, .nationalGrassland, .blmMonument, .blmConservationArea,
             .wildlifeRefuge, .naturalLandmark, .scenicByway:
            .federalSite
        }
    }

    /// Byways are drawn as lines rather than pins.
    public var isLinear: Bool {
        self == .scenicByway
    }

    public var defaultAgency: Agency {
        switch self {
        case .nationalPark, .npsUnit, .naturalLandmark: .nps
        case .nationalForest, .nationalGrassland: .forestService
        case .blmMonument, .blmConservationArea: .blm
        case .wildlifeRefuge: .fishAndWildlife
        case .statePark: .stateAgency
        case .scenicByway: .other
        }
    }
}

public enum Season: String, CaseIterable, Sendable, Codable, Identifiable {
    case spring, summer, autumn, winter

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        case .winter: "Winter"
        }
    }

    /// The season a month falls in, on the meteorological northern-hemisphere boundaries.
    public static func forMonth(_ month: Int) -> Season {
        switch month {
        case 3, 4, 5: .spring
        case 6, 7, 8: .summer
        case 9, 10, 11: .autumn
        default: .winter
        }
    }
}

/// The at-a-glance figures a guide opens with (SPECIFICATION.md §6, panel 3).
///
/// Every field is optional on purpose. The pipeline fills what the source data actually
/// carries, and an absent figure renders as absent. A plausible invented number would
/// reach the user as a fact, so there are no defaults here.
public struct PlaceFacts: Hashable, Sendable, Codable {
    public var establishedYear: Int?
    public var areaAcres: Double?
    public var lowestElevationMetres: Double?
    public var highestElevationMetres: Double?
    public var annualVisits: Int?
    public var annualVisitsYear: Int?
    public var entranceFee: String?
    public var bestSeasons: [Season]
    public var suggestedTime: String?

    public init(
        establishedYear: Int? = nil,
        areaAcres: Double? = nil,
        lowestElevationMetres: Double? = nil,
        highestElevationMetres: Double? = nil,
        annualVisits: Int? = nil,
        annualVisitsYear: Int? = nil,
        entranceFee: String? = nil,
        bestSeasons: [Season] = [],
        suggestedTime: String? = nil
    ) {
        self.establishedYear = establishedYear
        self.areaAcres = areaAcres
        self.lowestElevationMetres = lowestElevationMetres
        self.highestElevationMetres = highestElevationMetres
        self.annualVisits = annualVisits
        self.annualVisitsYear = annualVisitsYear
        self.entranceFee = entranceFee
        self.bestSeasons = bestSeasons
        self.suggestedTime = suggestedTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        establishedYear = try container.decodeIfPresent(Int.self, forKey: .establishedYear)
        areaAcres = try container.decodeIfPresent(Double.self, forKey: .areaAcres)
        lowestElevationMetres = try container.decodeIfPresent(
            Double.self, forKey: .lowestElevationMetres
        )
        highestElevationMetres = try container.decodeIfPresent(
            Double.self, forKey: .highestElevationMetres
        )
        annualVisits = try container.decodeIfPresent(Int.self, forKey: .annualVisits)
        annualVisitsYear = try container.decodeIfPresent(Int.self, forKey: .annualVisitsYear)
        entranceFee = try container.decodeIfPresent(String.self, forKey: .entranceFee)
        bestSeasons = try container.decodeIfPresent([Season].self, forKey: .bestSeasons) ?? []
        suggestedTime = try container.decodeIfPresent(String.self, forKey: .suggestedTime)
    }

    public var isEmpty: Bool {
        establishedYear == nil
            && areaAcres == nil
            && lowestElevationMetres == nil
            && highestElevationMetres == nil
            && annualVisits == nil
            && entranceFee == nil
            && bestSeasons.isEmpty
            && suggestedTime == nil
    }
}

/// A place on the map: a park, unit, forest, refuge, landmark or byway.
///
/// Reference data. Replaced wholesale by the pipeline on each release, so user records
/// only ever hold its `id`.
public struct Place: Identifiable, Hashable, Sendable, Codable {
    public let id: UnigridsID
    public let name: String
    /// The official designation as it reads beneath the title band: "National Park",
    /// "National Monument and Preserve", "State Park".
    public let designation: String
    public let kind: PlaceKind
    public let agency: Agency
    public let states: [USState]
    public let centre: Coordinate
    public let extent: BoundingBox?
    /// The NPS four-letter park code, where the place is an NPS unit.
    public let npsParkCode: String?
    /// The PAD-US unit identifier, where the place came from PAD-US.
    public let padUSID: String?
    /// A curated passport region, overriding the state-based fallback.
    public let passportRegion: PassportRegion?
    public let themes: [UnigridsID]
    public let facts: PlaceFacts
    public let officialURL: URL?

    public var tier: PlaceTier {
        kind.tier
    }

    /// The region this place stamps in.
    public var resolvedPassportRegion: PassportRegion {
        if let passportRegion {
            return passportRegion
        }
        guard let first = states.first else { return .western }
        return PassportRegion.byState(first)
    }

    /// "Utah", or "Tennessee · North Carolina" for a park that straddles a line.
    public var statesDescription: String {
        states.map(\.name).joined(separator: " · ")
    }

    public init(
        id: UnigridsID,
        name: String,
        designation: String,
        kind: PlaceKind,
        agency: Agency? = nil,
        states: [USState],
        centre: Coordinate,
        extent: BoundingBox? = nil,
        npsParkCode: String? = nil,
        padUSID: String? = nil,
        passportRegion: PassportRegion? = nil,
        themes: [UnigridsID] = [],
        facts: PlaceFacts = PlaceFacts(),
        officialURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.designation = designation
        self.kind = kind
        self.agency = agency ?? kind.defaultAgency
        self.states = states
        self.centre = centre
        self.extent = extent
        self.npsParkCode = npsParkCode
        self.padUSID = padUSID
        self.passportRegion = passportRegion
        self.themes = themes
        self.facts = facts
        self.officialURL = officialURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UnigridsID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(PlaceKind.self, forKey: .kind)
        designation = try container.decodeIfPresent(String.self, forKey: .designation)
            ?? Place.defaultDesignation(for: kind)
        agency = try container.decodeIfPresent(Agency.self, forKey: .agency)
            ?? kind.defaultAgency
        states = try container.decodeIfPresent([USState].self, forKey: .states) ?? []
        centre = try container.decode(Coordinate.self, forKey: .centre)
        extent = try container.decodeIfPresent(BoundingBox.self, forKey: .extent)
        npsParkCode = try container.decodeIfPresent(String.self, forKey: .npsParkCode)
        padUSID = try container.decodeIfPresent(String.self, forKey: .padUSID)
        passportRegion = try container.decodeIfPresent(
            PassportRegion.self, forKey: .passportRegion
        )
        themes = try container.decodeIfPresent([UnigridsID].self, forKey: .themes) ?? []
        facts = try container.decodeIfPresent(PlaceFacts.self, forKey: .facts) ?? PlaceFacts()
        officialURL = try container.decodeIfPresent(URL.self, forKey: .officialURL)
    }

    private static func defaultDesignation(for kind: PlaceKind) -> String {
        switch kind {
        case .nationalPark: "National Park"
        case .npsUnit: "National Park Service unit"
        case .statePark: "State Park"
        case .nationalForest: "National Forest"
        case .nationalGrassland: "National Grassland"
        case .blmMonument: "National Monument"
        case .blmConservationArea: "National Conservation Area"
        case .wildlifeRefuge: "National Wildlife Refuge"
        case .naturalLandmark: "National Natural Landmark"
        case .scenicByway: "Scenic Byway"
        }
    }
}
