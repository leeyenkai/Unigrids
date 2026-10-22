import Foundation

/// What sort of site a place is: the pictogram on its pin and its row in the map key
/// (SPECIFICATION.md §5, §14).
///
/// Finer than `PlaceKind`, which fixes how deep the app goes on a place, and independent
/// of `Agency`, which fixes the ink. Neither tells a battlefield from a seashore, which is
/// what a reader scanning the map wants to know. The NPS alone uses some forty
/// designations, so they are grouped into the handful a map key can carry, read off each
/// place's own designation rather than curated by hand.
public enum SiteType: String, CaseIterable, Sendable, Codable, Identifiable, Comparable {
    case nationalPark
    case nationalMonument
    case nationalPreserve
    case historicSite
    case battlefield
    case memorial
    case seashore
    case recreationArea
    case river
    case parkway
    case otherNPSSite
    case statePark
    case nationalForest
    case nationalGrassland
    case wildlifeRefuge
    case conservationArea
    case naturalLandmark
    case scenicByway

    public var id: String {
        rawValue
    }

    public static func < (lhs: SiteType, rhs: SiteType) -> Bool {
        guard let left = allCases.firstIndex(of: lhs),
              let right = allCases.firstIndex(of: rhs)
        else { return false }
        return left < right
    }

    /// The type a place belongs to.
    public init(place: Place) {
        self = SiteType.classify(kind: place.kind, designation: place.designation)
    }

    /// The type for a kind and an official designation.
    ///
    /// Order matters, because designations compound: "National River and Recreation Area"
    /// is a river, "Memorial Parkway" a parkway, "National Monument and Historic Shrine" a
    /// monument, "National Historical Park and Preserve" a historic site.
    public static func classify(kind: PlaceKind, designation: String) -> SiteType {
        switch kind {
        case .nationalPark: .nationalPark
        case .statePark: .statePark
        case .nationalForest: .nationalForest
        case .nationalGrassland: .nationalGrassland
        case .wildlifeRefuge: .wildlifeRefuge
        case .blmConservationArea: .conservationArea
        case .naturalLandmark: .naturalLandmark
        case .scenicByway: .scenicByway
        case .blmMonument:
            designation.lowercased().contains("monument") ? .nationalMonument
                : .conservationArea
        case .npsUnit:
            npsType(designation.lowercased())
        }
    }

    private static func npsType(_ designation: String) -> SiteType {
        let rules: [(SiteType, [String])] = [
            (.river, ["river", "riverway"]),
            (.parkway, ["parkway"]),
            (.battlefield, ["battlefield", "military park"]),
            (.seashore, ["seashore", "lakeshore"]),
            (.recreationArea, ["recreation area"]),
            (.memorial, ["memorial"]),
            (.nationalMonument, ["monument"]),
            (.historicSite, ["historic", "historical"]),
            (.nationalPreserve, ["preserve", "reserve"]),
        ]
        for (type, needles) in rules where needles.contains(where: designation.contains) {
            return type
        }
        return .otherNPSSite
    }

    /// The type's name in the map key, plural: "Battlefields".
    public var name: String {
        switch self {
        case .nationalPark: "National parks"
        case .nationalMonument: "National monuments"
        case .nationalPreserve: "Preserves and reserves"
        case .historicSite: "Historic sites and parks"
        case .battlefield: "Battlefields and military parks"
        case .memorial: "Memorials"
        case .seashore: "Seashores and lakeshores"
        case .recreationArea: "Recreation areas"
        case .river: "Rivers and riverways"
        case .parkway: "Parkways"
        case .otherNPSSite: "Other NPS sites"
        case .statePark: "State parks"
        case .nationalForest: "National forests"
        case .nationalGrassland: "National grasslands"
        case .wildlifeRefuge: "Wildlife refuges"
        case .conservationArea: "Conservation areas"
        case .naturalLandmark: "Natural landmarks"
        case .scenicByway: "Scenic byways"
        }
    }

    /// One of them: "Battlefield".
    public var singularName: String {
        switch self {
        case .nationalPark: "National park"
        case .nationalMonument: "National monument"
        case .nationalPreserve: "Preserve"
        case .historicSite: "Historic site"
        case .battlefield: "Battlefield"
        case .memorial: "Memorial"
        case .seashore: "Seashore"
        case .recreationArea: "Recreation area"
        case .river: "River"
        case .parkway: "Parkway"
        case .otherNPSSite: "NPS site"
        case .statePark: "State park"
        case .nationalForest: "National forest"
        case .nationalGrassland: "National grassland"
        case .wildlifeRefuge: "Wildlife refuge"
        case .conservationArea: "Conservation area"
        case .naturalLandmark: "Natural landmark"
        case .scenicByway: "Scenic byway"
        }
    }

    /// One line on what the type covers, for the map key.
    public var detail: String {
        switch self {
        case .nationalPark: "The 63, each with a full guide"
        case .nationalMonument: "NPS, BLM and Forest Service monuments"
        case .nationalPreserve: "NPS preserves and reserves"
        case .historicSite: "Historic sites, historical parks and areas"
        case .battlefield: "Battlefields, battlefield parks and military parks"
        case .memorial: "National memorials"
        case .seashore: "National seashores and lakeshores"
        case .recreationArea: "National recreation areas"
        case .river: "National rivers, riverways and wild and scenic rivers"
        case .parkway: "Parkways the NPS runs"
        case .otherNPSSite: "Parks and sites with no other designation"
        case .statePark: "A selection of well-known state parks"
        case .nationalForest: "Every national forest, at its proclaimed boundary"
        case .nationalGrassland: "Every national grassland"
        case .wildlifeRefuge: "Every national wildlife refuge"
        case .conservationArea: "BLM conservation areas and similar designations"
        case .naturalLandmark: "National Natural Landmarks, as points"
        case .scenicByway: "National Scenic Byways and All-American Roads"
        }
    }

    /// The tier the key draws the type's pin in. A place's own pin takes its shape from
    /// its own tier, so a BLM monument is a diamond on the map though the key's monument
    /// is the NPS's small square.
    public var tier: PlaceTier {
        switch self {
        case .nationalPark: .nationalPark
        case .nationalMonument, .nationalPreserve, .historicSite, .battlefield, .memorial,
             .seashore, .recreationArea, .river, .parkway, .otherNPSSite:
            .npsUnit
        case .statePark: .statePark
        case .nationalForest, .nationalGrassland, .wildlifeRefuge, .conservationArea,
             .naturalLandmark, .scenicByway:
            .federalSite
        }
    }

    /// The agency whose ink the key draws the type in. A monument can be anybody's; the
    /// key shows the NPS's and the map shows each place in its own.
    public var typicalAgency: Agency {
        switch self {
        case .nationalPark, .nationalMonument, .nationalPreserve, .historicSite, .battlefield,
             .memorial, .seashore, .recreationArea, .river, .parkway, .otherNPSSite:
            .nps
        case .statePark: .stateAgency
        case .nationalForest, .nationalGrassland: .forestService
        case .wildlifeRefuge: .fishAndWildlife
        case .conservationArea: .blm
        case .naturalLandmark, .scenicByway: .other
        }
    }

    /// The groups the map key lists types under.
    public enum Group: String, CaseIterable, Sendable, Identifiable {
        case nationalParkService
        case otherPublicLands
        case statesAndLandmarks

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .nationalParkService: "National Park Service"
            case .otherPublicLands: "Other federal lands"
            case .statesAndLandmarks: "State parks, landmarks and byways"
            }
        }

        public var types: [SiteType] {
            SiteType.allCases.filter { $0.group == self }
        }
    }

    public var group: Group {
        switch self {
        case .nationalPark, .nationalMonument, .nationalPreserve, .historicSite, .battlefield,
             .memorial, .seashore, .recreationArea, .river, .parkway, .otherNPSSite:
            .nationalParkService
        case .nationalForest, .nationalGrassland, .wildlifeRefuge, .conservationArea:
            .otherPublicLands
        case .statePark, .naturalLandmark, .scenicByway:
            .statesAndLandmarks
        }
    }
}

extension Place {
    /// The place's site type, for its pin and the map key.
    public var siteType: SiteType {
        SiteType(place: self)
    }

    /// A sentence built only from what the dataset says — type, states, agency — for a
    /// place nobody has written an overview of. Never more than the fields carry.
    public var factualDescription: String {
        // A byway's designation is a proper name — All-American Road — and keeps its
        // capitals; a type is a common noun and does not.
        let noun = kind == .scenicByway ? designation : siteType.singularName.lowercased()
        let article = noun.lowercased().first.map { "aeiou".contains($0) } == true ? "An" : "A"
        var sentence = "\(article) \(noun)"
        if !states.isEmpty {
            let names = states.map(\.name)
            let list = names.count <= 2 ? names.joined(separator: " and ")
                : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
            sentence += " in \(list)"
        }
        switch agency {
        case .nps, .forestService, .blm, .fishAndWildlife:
            sentence += ", managed by the \(agency.name)"
        case .stateAgency:
            sentence += ", run by the state"
        case .other:
            if kind == .naturalLandmark {
                sentence += ", recognised by the National Park Service's National Natural "
                    + "Landmarks Program"
            } else if kind == .scenicByway {
                sentence += ", designated by the US Department of Transportation"
            }
        }
        return sentence + "."
    }
}
