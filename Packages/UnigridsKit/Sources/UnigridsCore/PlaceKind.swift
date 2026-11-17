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

/// The body behind a place: who manages it, or abroad, who designates it.
public enum Agency: String, CaseIterable, Sendable, Codable {
    case nps
    case forestService
    case blm
    case fishAndWildlife
    case stateAgency
    case other
    /// Japan's Ministry of the Environment, which designates and manages the national
    /// parks.
    case environmentMinistryJapan
    /// A Japanese prefecture, which runs a quasi-national park the ministry designates.
    case prefecture
    /// The Norwegian Environment Agency (Miljødirektoratet). Each park or reserve is run
    /// locally — by a board or the county governor — and `Place.managedBy` names that body.
    case environmentAgencyNorway

    public var shortName: String {
        switch self {
        case .nps: "NPS"
        case .forestService: "USFS"
        case .blm: "BLM"
        case .fishAndWildlife: "USFWS"
        case .stateAgency: "State"
        case .other: "Other"
        case .environmentMinistryJapan: "MOE"
        case .prefecture: "Prefecture"
        case .environmentAgencyNorway: "Miljødirektoratet"
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
        case .environmentMinistryJapan: "Ministry of the Environment, Japan"
        case .prefecture: "Prefectural government"
        case .environmentAgencyNorway: "Norwegian Environment Agency"
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
    /// Japan's quasi-national parks (国定公園): designated by the ministry, run by the
    /// prefectures, so drawn as state parks are.
    case quasiNationalPark
    /// Norway's landscape protection areas (landskapsvernområder).
    case protectedLandscape
    /// Norway's larger nature reserves (naturreservater), SPECIFICATION.md §17, item 22.
    case natureReserve

    public var tier: PlaceTier {
        switch self {
        case .nationalPark: .nationalPark
        case .npsUnit: .npsUnit
        case .statePark, .quasiNationalPark: .statePark
        case .nationalForest, .nationalGrassland, .blmMonument, .blmConservationArea,
             .wildlifeRefuge, .naturalLandmark, .scenicByway, .protectedLandscape,
             .natureReserve:
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
        case .quasiNationalPark: .prefecture
        case .protectedLandscape, .natureReserve: .environmentAgencyNorway
        }
    }
}
