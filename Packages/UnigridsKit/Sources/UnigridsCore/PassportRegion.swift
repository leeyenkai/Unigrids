import Foundation

/// One of the nine regions the paper NPS passport organises its stamp pages by
/// (SPECIFICATION.md §9).
///
/// Each region cancels in its own ink colour, as the paper book does, and each opens with
/// a title page carrying a small map and a stamped-so-far count.
public enum PassportRegion: String, CaseIterable, Sendable, Codable, Identifiable {
    case northAtlantic
    case midAtlantic
    case nationalCapital
    case southeast
    case midwest
    case southwest
    case rockyMountain
    case western
    case pacificNorthwestAndAlaska

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .northAtlantic: "North Atlantic"
        case .midAtlantic: "Mid-Atlantic"
        case .nationalCapital: "National Capital"
        case .southeast: "Southeast"
        case .midwest: "Midwest"
        case .southwest: "Southwest"
        case .rockyMountain: "Rocky Mountain"
        case .western: "Western"
        case .pacificNorthwestAndAlaska: "Pacific Northwest and Alaska"
        }
    }

    /// The region's cancellation ink.
    ///
    /// This is **Unigrids' own palette**, chosen to be mutually distinguishable and to sit
    /// in the ink-on-paper range. It approximates the paper passport's regional scheme
    /// rather than reproducing documented values — the official colours are part of the
    /// one-time curation in SPECIFICATION.md §17, follow-up 3, and this palette should be
    /// corrected when that lands.
    ///
    /// Two values per region, not one. A stamp lands on a native passport page, and the
    /// dark ones are the same hue lifted until they clear 4.5:1 against the lightest dark
    /// surface — body text, not decoration, because the site name on a 112-point stamp
    /// sets at about 10.6 points.
    public func ink(_ scheme: PaletteScheme) -> ColorValue {
        let hex = switch scheme {
        case .light: lightInkHex
        case .dark: darkInkHex
        }
        return ColorValue(hex: hex) ?? ColorValue(red: 0, green: 0, blue: 0)
    }

    private var lightInkHex: String {
        switch self {
        case .northAtlantic: "1F4E79"
        case .midAtlantic: "6A3D7C"
        case .nationalCapital: "8C2F39"
        case .southeast: "1D6F42"
        case .midwest: "A85A1E"
        case .southwest: "B5451B"
        case .rockyMountain: "2F5D50"
        case .western: "8A6A12"
        case .pacificNorthwestAndAlaska: "1C6E7E"
        }
    }

    private var darkInkHex: String {
        switch self {
        case .northAtlantic: "5F9DD6"
        case .midAtlantic: "B489C5"
        case .nationalCapital: "D5818A"
        case .southeast: "2DAD67"
        case .midwest: "DC823C"
        case .southwest: "E57B54"
        case .rockyMountain: "54A78F"
        case .western: "BD9219"
        case .pacificNorthwestAndAlaska: "2AA6BE"
        }
    }

    /// Display order, matching the sequence the paper book binds its sections in.
    public var order: Int {
        PassportRegion.allCases.firstIndex(of: self) ?? 0
    }

    /// The region a place falls in when it has no curated assignment.
    ///
    /// The specification (§9) assigns NPS sites by the paper passport's own region map,
    /// curated once in the pipeline, and everything else by state. Until that curation
    /// exists, this state map is the fallback for both — a best-effort grouping, not the
    /// paper book's authority. A `Place` carrying an explicit `passportRegion` always
    /// wins over this.
    public static func byState(_ state: USState) -> PassportRegion {
        stateAssignments[state.code] ?? .western
    }

    /// Every state, district and territory, mapped to the region it stamps in.
    ///
    /// Public so the passport's "Beyond the NPS" sections can group state parks and
    /// federal sites without each caller rebuilding the map, and so a test can assert the
    /// map is total rather than silently falling through to a default.
    public static let stateAssignments: [String: PassportRegion] = [
        "CT": .northAtlantic, "ME": .northAtlantic, "MA": .northAtlantic,
        "NH": .northAtlantic, "NY": .northAtlantic, "RI": .northAtlantic,
        "VT": .northAtlantic,

        "DE": .midAtlantic, "NJ": .midAtlantic, "PA": .midAtlantic,
        "WV": .midAtlantic,

        "DC": .nationalCapital, "MD": .nationalCapital, "VA": .nationalCapital,

        "AL": .southeast, "FL": .southeast, "GA": .southeast, "KY": .southeast,
        "MS": .southeast, "NC": .southeast, "SC": .southeast, "TN": .southeast,
        "PR": .southeast, "VI": .southeast,

        "IA": .midwest, "IL": .midwest, "IN": .midwest, "KS": .midwest,
        "MI": .midwest, "MN": .midwest, "MO": .midwest, "NE": .midwest,
        "ND": .midwest, "OH": .midwest, "SD": .midwest, "WI": .midwest,

        "AR": .southwest, "AZ": .southwest, "LA": .southwest, "NM": .southwest,
        "OK": .southwest, "TX": .southwest,

        "CO": .rockyMountain, "MT": .rockyMountain, "UT": .rockyMountain,
        "WY": .rockyMountain,

        "CA": .western, "NV": .western, "HI": .western,
        "AS": .western, "GU": .western, "MP": .western,

        "AK": .pacificNorthwestAndAlaska, "ID": .pacificNorthwestAndAlaska,
        "OR": .pacificNorthwestAndAlaska, "WA": .pacificNorthwestAndAlaska,
    ]
}
