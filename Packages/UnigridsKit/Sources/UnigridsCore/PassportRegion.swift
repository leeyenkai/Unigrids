import Foundation

/// A region of a passport book (SPECIFICATION.md §9): the nine the paper NPS passport
/// organises its stamp pages by, then Japan's eight and Norway's six (ADR 0013).
///
/// Each region cancels in its own ink colour, as the paper book does, and each opens with
/// a title page carrying a small map and a stamped-so-far count. The regions abroad are
/// Unigrids' own grouping, with no paper book to follow (§17, item 24): Japan's after the
/// Ministry of the Environment's regional offices, Norway's after the landsdeler.
///
/// New cases go at the end: `order` is the position within a country's book.
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

    case hokkaido
    case tohoku
    case kanto
    case chubu
    case kinki
    case chugokuShikoku
    case kyushu
    case okinawaAmami

    case northernNorway
    case trondelag
    case westernNorway
    case easternNorway
    case southernNorway
    case svalbard

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
        case .hokkaido: "Hokkaido"
        case .tohoku: "Tohoku"
        case .kanto: "Kanto"
        case .chubu: "Chubu"
        case .kinki: "Kinki"
        case .chugokuShikoku: "Chugoku and Shikoku"
        case .kyushu: "Kyushu"
        case .okinawaAmami: "Okinawa and Amami"
        case .northernNorway: "Northern Norway"
        case .trondelag: "Trøndelag"
        case .westernNorway: "Western Norway"
        case .easternNorway: "Eastern Norway"
        case .southernNorway: "Southern Norway"
        case .svalbard: "Svalbard"
        }
    }

    /// The book the region belongs to.
    public var country: Country {
        switch self {
        case .northAtlantic, .midAtlantic, .nationalCapital, .southeast, .midwest,
             .southwest, .rockyMountain, .western, .pacificNorthwestAndAlaska:
            .unitedStates
        case .hokkaido, .tohoku, .kanto, .chubu, .kinki, .chugokuShikoku, .kyushu,
             .okinawaAmami:
            .japan
        case .northernNorway, .trondelag, .westernNorway, .easternNorway, .southernNorway,
             .svalbard:
            .norway
        }
    }

    /// A country's regions, in the order its book binds them.
    public static func regions(in country: Country) -> [PassportRegion] {
        allCases.filter { $0.country == country }
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
        case .hokkaido: "2B4C7E"
        case .tohoku: "3E6B48"
        case .kanto: "9E3D22"
        case .chubu: "5B4A8A"
        case .kinki: "8E2F4E"
        case .chugokuShikoku: "7A5A12"
        case .kyushu: "5E6B1C"
        case .okinawaAmami: "0E6E74"
        case .northernNorway: "2E5A88"
        case .trondelag: "4C6B2F"
        case .westernNorway: "1F6F6A"
        case .easternNorway: "8A4B1F"
        case .southernNorway: "A3402E"
        case .svalbard: "5A4A86"
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
        case .hokkaido: "7599D0"
        case .tohoku: "64A573"
        case .kanto: "DD7D62"
        case .chubu: "9E90C3"
        case .kinki: "D47D99"
        case .chugokuShikoku: "C3901D"
        case .kyushu: "8CA02A"
        case .okinawaAmami: "15A8B1"
        case .northernNorway: "6B9BCD"
        case .trondelag: "76A549"
        case .westernNorway: "2FA9A1"
        case .easternNorway: "D68348"
        case .southernNorway: "D78070"
        case .svalbard: "9D90C2"
        }
    }

    /// Display order within the region's book, matching the sequence the paper book binds
    /// its sections in for the US.
    public var order: Int {
        PassportRegion.regions(in: country).firstIndex(of: self) ?? 0
    }

    /// The region a place abroad stamps in when its record names none. Bundled data never
    /// reaches this — a test holds every place abroad to a curated region — but a value
    /// type has to answer something, and an American region would be the wrong book.
    public static func fallback(in country: Country) -> PassportRegion {
        switch country {
        case .unitedStates: .western
        case .japan: .hokkaido
        case .norway: .northernNorway
        }
    }

    /// The region a place falls in when it has no curated assignment.
    ///
    /// The paper book keeps the nine NPS regions in force when the programme began, and
    /// files a site by where it is — so a state decides, with a few sites filed elsewhere
    /// (the DC-area parks in Maryland, Ellis Island under New York) carried as explicit
    /// `passportRegion`s from `Pipeline/content/curated/passport-regions.json`. A `Place`
    /// carrying one always wins over this.
    public static func byState(_ state: USState) -> PassportRegion {
        stateAssignments[state.code] ?? .western
    }

    /// Every state, district and territory, mapped to the region it stamps in.
    ///
    /// Checked against the 329 regional stamps of the annual series, 1986 onward, each a
    /// named park filed under a region (the Wikipedia article on the programme, revision
    /// 1371719587). Every state's parks agree with its row here, the sites in the curated
    /// file apart. Earlier guesses had Arizona in Southwest (its fourteen stamps are all
    /// Western), Virginia and Maryland in National Capital (Mid-Atlantic, the DC-area
    /// parks apart) and the Dakotas in Midwest (Rocky Mountain).
    ///
    /// Public so the passport's "Beyond the NPS" sections can group state parks and
    /// federal sites without each caller rebuilding the map, and so a test can assert the
    /// map is total rather than silently falling through to a default.
    public static let stateAssignments: [String: PassportRegion] = [
        "CT": .northAtlantic, "ME": .northAtlantic, "MA": .northAtlantic,
        "NH": .northAtlantic, "NY": .northAtlantic, "RI": .northAtlantic,
        "VT": .northAtlantic,

        "DE": .midAtlantic, "MD": .midAtlantic, "NJ": .midAtlantic, "PA": .midAtlantic,
        "VA": .midAtlantic, "WV": .midAtlantic,

        "DC": .nationalCapital,

        "AL": .southeast, "FL": .southeast, "GA": .southeast, "KY": .southeast,
        "MS": .southeast, "NC": .southeast, "SC": .southeast, "TN": .southeast,
        "PR": .southeast, "VI": .southeast,

        "IA": .midwest, "IL": .midwest, "IN": .midwest, "KS": .midwest,
        "MI": .midwest, "MN": .midwest, "MO": .midwest, "NE": .midwest,
        "OH": .midwest, "WI": .midwest,

        "AR": .southwest, "LA": .southwest, "NM": .southwest, "OK": .southwest,
        "TX": .southwest,

        "CO": .rockyMountain, "MT": .rockyMountain, "ND": .rockyMountain,
        "SD": .rockyMountain, "UT": .rockyMountain, "WY": .rockyMountain,

        "AZ": .western, "CA": .western, "NV": .western, "HI": .western,
        "AS": .western, "GU": .western, "MP": .western,

        "AK": .pacificNorthwestAndAlaska, "ID": .pacificNorthwestAndAlaska,
        "OR": .pacificNorthwestAndAlaska, "WA": .pacificNorthwestAndAlaska,
    ]
}

/// Which passport slot an impression sits in (SPECIFICATION.md §9: a site with several
/// official stamp locations gets one slot per location).
///
/// One rule for the region page and the impressions sheet, which once disagreed: a stamp
/// with no location sat in the first slot on the page and in every slot in the sheet.
public enum PassportSlotRule {
    /// The location whose slot holds a stamp made at `stampLocation`, among a site's slot
    /// locations in order — nil when the site has a single slot. A stamp made with no
    /// location chosen, or at a location the dataset no longer lists, sits in the first.
    public static func slot(
        for stampLocation: UnigridsID?,
        among locations: [UnigridsID]
    ) -> UnigridsID? {
        guard locations.count >= 2 else { return nil }
        if let stampLocation, locations.contains(stampLocation) {
            return stampLocation
        }
        return locations.first
    }
}
