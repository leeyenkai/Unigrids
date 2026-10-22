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
    /// How the elevation range was found, where it was measured rather than published:
    /// the guide shows it beneath the figures.
    public var elevationNote: String?

    public init(
        establishedYear: Int? = nil,
        areaAcres: Double? = nil,
        lowestElevationMetres: Double? = nil,
        highestElevationMetres: Double? = nil,
        annualVisits: Int? = nil,
        annualVisitsYear: Int? = nil,
        entranceFee: String? = nil,
        bestSeasons: [Season] = [],
        suggestedTime: String? = nil,
        elevationNote: String? = nil
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
        self.elevationNote = elevationNote
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
        elevationNote = try container.decodeIfPresent(String.self, forKey: .elevationNote)
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
    /// A short overview: what the place is and why anyone goes. Shown on the map card and
    /// at the top of a place's page. NPS-authored for NPS units, written for Unigrids
    /// elsewhere; `summarySource` says which.
    public let summary: String?
    /// Who wrote `summary`, for the credit line beneath it.
    public let summarySource: String?
    /// The lead photograph, with the credit it must carry.
    public let image: GuideImage?
    /// Somewhere to read more, where the place has no official page Unigrids can link.
    public let infoURL: URL?
    /// What a visitor can do there, as the managing agency lists it. Empty when no
    /// source says, which is not the same as nothing to do.
    public let activities: [PlaceActivity]
    /// The IANA time zone at the place, for which calendar day a visit fell on there.
    public let timeZoneID: String?
    /// Where `summary` came from, when it is someone else's text to credit and link:
    /// a Wikipedia article's lead, under `summaryLicence`.
    public let summaryURL: URL?
    public let summaryLicence: String?
    /// Monthly recreation visits, for an NPS site: how busy each month is.
    public let visitation: MonthlyVisitation?
    /// Fees, hours, directions and contact for an NPS site without a full guide.
    public let visitorInfo: PlaceVisitorInfo?
    /// The body that runs a state park, as PAD-US names it: "Colorado State Parks".
    public let managedBy: String?

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
        officialURL: URL? = nil,
        summary: String? = nil,
        summarySource: String? = nil,
        image: GuideImage? = nil,
        infoURL: URL? = nil,
        activities: [PlaceActivity] = [],
        timeZoneID: String? = nil,
        summaryURL: URL? = nil,
        summaryLicence: String? = nil,
        visitation: MonthlyVisitation? = nil,
        visitorInfo: PlaceVisitorInfo? = nil,
        managedBy: String? = nil
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
        self.summary = summary
        self.summarySource = summarySource
        self.image = image
        self.infoURL = infoURL
        self.activities = activities
        self.timeZoneID = timeZoneID
        self.summaryURL = summaryURL
        self.summaryLicence = summaryLicence
        self.visitation = visitation
        self.visitorInfo = visitorInfo
        self.managedBy = managedBy
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
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        summarySource = try container.decodeIfPresent(String.self, forKey: .summarySource)
        image = try container.decodeIfPresent(GuideImage.self, forKey: .image)
        infoURL = try container.decodeIfPresent(URL.self, forKey: .infoURL)
        // Unknown activity names from a newer dataset are dropped, not fatal.
        activities = (try? container.decodeIfPresent([String].self, forKey: .activities))?
            .flatMap { $0.compactMap(PlaceActivity.init(rawValue:)) } ?? []
        timeZoneID = try container.decodeIfPresent(String.self, forKey: .timeZoneID)
        summaryURL = try container.decodeIfPresent(URL.self, forKey: .summaryURL)
        summaryLicence = try container.decodeIfPresent(String.self, forKey: .summaryLicence)
        // A malformed optional block costs that block, never the place.
        visitation = try? container.decodeIfPresent(MonthlyVisitation.self, forKey: .visitation)
        visitorInfo = try? container.decodeIfPresent(PlaceVisitorInfo.self, forKey: .visitorInfo)
        managedBy = try container.decodeIfPresent(String.self, forKey: .managedBy)
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

/// How busy an NPS site is in each calendar month: the mean of the NPS's own monthly
/// recreation visit counts over `years` (SPECIFICATION.md §10, weather versus crowds).
public struct MonthlyVisitation: Hashable, Sendable, Codable {
    /// Twelve figures, January first.
    public let monthly: [Int]
    /// The first and last year averaged.
    public let years: [Int]

    public init(monthly: [Int], years: [Int]) {
        self.monthly = monthly
        self.years = years
    }

    /// "2022–2025", for the credit line.
    public var yearsDescription: String {
        guard let first = years.first, let last = years.last else { return "" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    /// The busiest and quietest months, 1-based, or nil without twelve figures.
    public var busiestMonth: Int? {
        guard monthly.count == 12 else { return nil }
        return monthly.indices.max { monthly[$0] < monthly[$1] }.map { $0 + 1 }
    }

    public var quietestMonth: Int? {
        guard monthly.count == 12 else { return nil }
        return monthly.indices.min { monthly[$0] < monthly[$1] }.map { $0 + 1 }
    }

    /// A month's share of the busiest month, 0 to 1, for a bar.
    public func share(ofMonth month: Int) -> Double {
        guard monthly.indices.contains(month - 1), let peak = monthly.max(), peak > 0 else {
            return 0
        }
        return Double(monthly[month - 1]) / Double(peak)
    }
}

/// What a visitor needs before going to an NPS site without a full guide — the same
/// fields a national park's guide carries in Plan your visit and Getting there, as the
/// NPS publishes them.
public struct PlaceVisitorInfo: Hashable, Sendable, Codable {
    public let fees: [EntranceFee]
    public let operatingHours: String?
    public let directions: String?
    public let weather: String?
    public let reservations: String?
    public let phone: String?
    public let email: String?

    public init(
        fees: [EntranceFee] = [],
        operatingHours: String? = nil,
        directions: String? = nil,
        weather: String? = nil,
        reservations: String? = nil,
        phone: String? = nil,
        email: String? = nil
    ) {
        self.fees = fees
        self.operatingHours = operatingHours
        self.directions = directions
        self.weather = weather
        self.reservations = reservations
        self.phone = phone
        self.email = email
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fees = (try? container.decodeIfPresent([EntranceFee].self, forKey: .fees)) ?? []
        operatingHours = try container.decodeIfPresent(String.self, forKey: .operatingHours)
        directions = try container.decodeIfPresent(String.self, forKey: .directions)
        weather = try container.decodeIfPresent(String.self, forKey: .weather)
        reservations = try container.decodeIfPresent(String.self, forKey: .reservations)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    public var isEmpty: Bool {
        fees.isEmpty && operatingHours == nil && directions == nil && weather == nil
            && reservations == nil && phone == nil && email == nil
    }
}

extension Place {
    /// The line that credits a summary not written for Unigrids: "Adapted from the
    /// Wikipedia article “Golden Gate Canyon State Park”, CC BY-SA 4.0" for a shortened
    /// lead, "From the National Park Service" for the agency's own words. Nil for prose
    /// written for the app, which the page credits as a whole.
    public var summaryCredit: String? {
        guard summary != nil, let source = summarySource, source != "Unigrids" else {
            return nil
        }
        guard source == "Wikipedia" else { return "From the \(source)" }
        let licence = summaryLicence.map { ", \($0)" } ?? ""
        let title = summaryURL?.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        guard let title, !title.isEmpty else { return "Adapted from Wikipedia" + licence }
        return "Adapted from the Wikipedia article \u{201C}\(title)\u{201D}" + licence
    }
}
