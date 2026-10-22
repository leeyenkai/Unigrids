import Foundation

/// The colour a place is drawn in on the map, by what kind of place it is (SPECIFICATION.md
/// §5: pins differ by type).
///
/// Colour carries the kind of place because it is what the eye sorts by first: a reader
/// scanning the map wants to tell a battlefield from a seashore from a forest before they
/// care who runs it. Related types share a colour — history is brown, water is blue, wild
/// land is green — and the pictogram tells them apart within it. The shape says who runs
/// the place (`PlaceTier`).
///
/// Eleven colours, chosen to sit at least 30 ΔE (CIE76) from one another, so no two read
/// as the same colour at pin size; a test holds them apart. National parks are black, the
/// Unigrid band: the one kind of place the map is about.
public enum SiteInk: String, CaseIterable, Sendable {
    case nationalPark
    case monument
    /// Historic sites, battlefields and memorials.
    case history
    /// Seashores and lakeshores, recreation areas and rivers.
    case water
    /// Forests, grasslands and preserves.
    case wildland
    case refuge
    /// BLM conservation areas.
    case conservation
    case landmark
    case statePark
    /// Parkways and scenic byways.
    case road
    /// NPS sites with no other designation.
    case other

    /// The ink for a place.
    public static func forPlace(_ place: Place) -> SiteInk {
        place.siteType.ink
    }

    /// The pin's fill, under a white pictogram and a white keyline, in both schemes.
    ///
    /// Pins sit on map tiles no palette controls, so they do not change with the scheme:
    /// the keyline separates them from a dark map and the fill from a light one. Every
    /// one holds a white pictogram at 3:1 or better.
    public var pin: ColorValue {
        ColorValue(hex: pinHex) ?? ColorValue(red: 0, green: 0, blue: 0)
    }

    /// The colour for everything else the kind of place draws: outlines and routes on the
    /// map, and its tint in lists. Lifted in the dark scheme, as the agency inks were, so
    /// it clears 3:1 on a dark surface; national parks go from black to near-white, since
    /// a black outline vanishes on a dark map.
    public func value(_ scheme: PaletteScheme) -> ColorValue {
        let hex = switch scheme {
        case .light: pinHex
        case .dark: darkHex
        }
        return ColorValue(hex: hex) ?? ColorValue(red: 0, green: 0, blue: 0)
    }

    /// The white the pictogram and keyline are drawn in.
    public static let pictogram = ColorValue(red: 1, green: 1, blue: 1)

    /// The disc behind the white tick on a visited place's pin: the green of "done",
    /// fixed rather than the palette's accent, because it sits on map tiles.
    public static let visitedTick = ColorValue(red: 0.118, green: 0.557, blue: 0.275)

    private var pinHex: String {
        switch self {
        case .nationalPark: "1A1A1A"
        case .monument: "B3243A"
        case .history: "7A4B2A"
        case .water: "1A72B8"
        case .wildland: "2F7A32"
        case .refuge: "00827E"
        case .conservation: "9A7A0A"
        case .landmark: "B02E8C"
        case .statePark: "6447C2"
        case .road: "D2600A"
        case .other: "767676"
        }
    }

    private var darkHex: String {
        switch self {
        case .nationalPark: "E6E6E6"
        case .monument: "DA455C"
        case .history: "AF6C3C"
        case .water: "1D80CE"
        case .wildland: "378E3A"
        case .refuge: "008A85"
        case .conservation: "A8860C"
        case .landmark: "CE43A7"
        case .statePark: "846DCF"
        case .road: "D2600A"
        case .other: "7C7C7C"
        }
    }
}

extension SiteType {
    /// The colour the type is drawn in.
    public var ink: SiteInk {
        switch self {
        case .nationalPark: .nationalPark
        case .nationalMonument: .monument
        case .historicSite, .battlefield, .memorial: .history
        case .seashore, .recreationArea, .river: .water
        case .nationalPreserve, .nationalForest, .nationalGrassland: .wildland
        case .wildlifeRefuge: .refuge
        case .conservationArea: .conservation
        case .naturalLandmark: .landmark
        case .statePark: .statePark
        case .parkway, .scenicByway: .road
        case .otherNPSSite: .other
        }
    }
}
