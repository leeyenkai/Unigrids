import Foundation

/// The colour a place is drawn in, by the agency behind it.
///
/// In `UnigridsCore` rather than in the design layer so the dark variants fall under the
/// same contrast suite as everything else, and so `CaseIterable` makes that suite total.
///
/// These are not palette colours and do not change with the palette: an agency's identity
/// is a property of the place, not of the reader's taste.
public enum AgencyInk: String, CaseIterable, Sendable {
    case nationalPark
    case npsUnit
    case forestService
    case blm
    case fishAndWildlife
    case stateAgency
    /// National Natural Landmarks, which belong to whoever owns the land and are drawn in
    /// their own ink rather than any one owner's.
    case landmark
    /// Scenic byways: a road, not a holding.
    case byway
    case other

    /// A place's ink. Landmarks and byways have no managing agency to take one from, so
    /// they have their own.
    public static func forPlace(_ place: Place) -> AgencyInk {
        switch place.kind {
        case .naturalLandmark: .landmark
        case .scenicByway: .byway
        default: forPlace(agency: place.agency, tier: place.tier)
        }
    }

    /// The ink a site type is keyed in.
    public static func forType(_ type: SiteType) -> AgencyInk {
        switch type {
        case .naturalLandmark: .landmark
        case .scenicByway: .byway
        default: forPlace(agency: type.typicalAgency, tier: type.tier)
        }
    }

    /// National parks get their own ink, a tier up from the rest of the NPS.
    public static func forPlace(agency: Agency, tier: PlaceTier) -> AgencyInk {
        switch agency {
        case .nps: tier == .nationalPark ? .nationalPark : .npsUnit
        case .forestService: .forestService
        case .blm: .blm
        case .fishAndWildlife: .fishAndWildlife
        case .stateAgency: .stateAgency
        case .other: .other
        }
    }

    /// The ink for one scheme.
    ///
    /// Dark variants keep the light hue and lift lightness only, so a refuge stays the same
    /// teal on a dark map as on a light one. They are drawn as icons and pin fills, so the
    /// bar is 3:1 against the lightest surface of the scheme rather than 4.5:1.
    public func value(_ scheme: PaletteScheme) -> ColorValue {
        let hex = switch scheme {
        case .light: lightHex
        case .dark: darkHex
        }
        return ColorValue(hex: hex) ?? ColorValue(red: 0, green: 0, blue: 0)
    }

    private var lightHex: String {
        switch self {
        case .nationalPark: "2E5339"
        case .npsUnit: "4A7C59"
        case .forestService: "2F6B3A"
        case .blm: "8A6A2F"
        case .fishAndWildlife: "2B6A7A"
        case .stateAgency: "5C6BA8"
        case .landmark: "7B4B94"
        case .byway: "A0522D"
        case .other: "6E6E73"
        }
    }

    private var darkHex: String {
        switch self {
        case .nationalPark: "509063"
        case .npsUnit: "558F66"
        case .forestService: "409350"
        case .blm: "A27D37"
        case .fishAndWildlife: "398DA2"
        case .stateAgency: "7480B5"
        case .landmark: "A57CBE"
        case .byway: "C8774A"
        case .other: "828288"
        }
    }
}
