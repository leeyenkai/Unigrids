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
    /// New Zealand's Department of Conservation (Te Papa Atawhai), which runs the national
    /// parks and the conservation and forest parks.
    case conservationDepartmentNZ
    /// Parks Australia, which runs the six Commonwealth national parks, three of them
    /// jointly with their Traditional Owners. The rest are the states' (`.stateAgency`).
    case parksAustralia
    /// Parks Canada, which runs the national parks, reserves and marine conservation areas.
    case parksCanada
    /// A Canadian province's park agency.
    case provincialAgency

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
        case .conservationDepartmentNZ: "DOC"
        case .parksAustralia: "Parks Australia"
        case .parksCanada: "Parks Canada"
        case .provincialAgency: "Province"
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
        case .conservationDepartmentNZ: "Department of Conservation, New Zealand"
        case .parksAustralia: "Parks Australia"
        case .parksCanada: "Parks Canada"
        case .provincialAgency: "Provincial park agency"
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
    /// New Zealand's conservation and forest parks, and Te Urewera: run by DOC (Te Urewera
    /// by its board), below the national parks.
    case conservationPark
    /// An Australian state's or territory's national park without a full guide: named a
    /// national park by its state, drawn as a state park is (ADR 0014).
    case stateNationalPark
    /// Canada's national marine conservation areas, run by Parks Canada.
    case marineConservationArea
    /// A Canadian provincial park of 100 km² or more — Québec's *parcs nationaux* among
    /// them, which are provincial whatever their name.
    case provincialPark

    public var tier: PlaceTier {
        switch self {
        case .nationalPark: .nationalPark
        case .npsUnit: .npsUnit
        case .statePark, .quasiNationalPark, .stateNationalPark, .provincialPark: .statePark
        case .nationalForest, .nationalGrassland, .blmMonument, .blmConservationArea,
             .wildlifeRefuge, .naturalLandmark, .scenicByway, .protectedLandscape,
             .natureReserve, .conservationPark, .marineConservationArea:
            .federalSite
        }
    }

    /// Byways are drawn as lines rather than pins.
    public var isLinear: Bool {
        self == .scenicByway
    }

    /// The agency a place of this kind in `country` answers to when its record names
    /// none: abroad never the NPS or another US agency (ADR 0013).
    public func defaultAgency(in country: Country) -> Agency {
        switch country {
        case .unitedStates: defaultAgency
        case .japan: self == .quasiNationalPark ? .prefecture : .environmentMinistryJapan
        case .norway: .environmentAgencyNorway
        case .newZealand: .conservationDepartmentNZ
        // Each record names its agency; the states run all but six parks.
        case .australia: .stateAgency
        case .canada: self == .provincialPark ? .provincialAgency : .parksCanada
        }
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
        case .conservationPark: .conservationDepartmentNZ
        case .stateNationalPark: .stateAgency
        case .marineConservationArea: .parksCanada
        case .provincialPark: .provincialAgency
        }
    }
}
