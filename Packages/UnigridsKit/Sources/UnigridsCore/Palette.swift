import Foundation

/// Light or dark, without SwiftUI. `UnigridsDesign` maps `ColorScheme` onto this.
public enum PaletteScheme: String, CaseIterable, Sendable, Identifiable, Codable {
    case light
    case dark

    public var id: String {
        rawValue
    }

    /// The native surfaces the app draws on but does not own.
    ///
    /// Semantic system colours have no value we can read, so contrast against them is
    /// asserted against these approximations of Apple's own. They matter because stamps,
    /// pins and tints land on native pages rather than on Unigrid paper: clearing the
    /// *lightest* dark surface clears the rest, which is why the list is not just black.
    public var referenceSurfaces: [(name: String, value: ColorValue)] {
        let hexes: [(String, String)] = switch self {
        case .light:
            [("systemBackground", "FFFFFF"), ("grouped", "F2F2F7")]
        case .dark:
            [("systemBackground", "000000"), ("secondary", "1C1C1E"), ("tertiary", "2C2C2E")]
        }
        return hexes.compactMap { name, hex in
            ColorValue(hex: hex).map { (name, $0) }
        }
    }
}

/// A named colour scheme for the Unigrid paper-and-ink family and the app's tint.
///
/// Distinct from `Theme`, which is a content tag on a place (geology, ecosystem, history).
/// Nothing here touches native surfaces: the map, trips, passport, stats and settings keep
/// semantic system colours (SPECIFICATION.md §14, AGENTS.md §6). A palette changes the
/// paper, the ink and the accent — not the chrome.
///
/// The band stays near-black in every palette. §6 asks for a black title band with the park
/// name reversed out of it, and that is the one part of the Unigrid that is not ours to
/// restyle; palettes vary its exact value, never its character.
public enum Palette: String, CaseIterable, Sendable, Identifiable, Codable {
    /// The 1977 brochure stock: warm off-white paper, near-black band, park green.
    case unigrid
    /// Ink on paper and nothing else. The America 250 seal is the only colour on the page.
    case press
    /// Sandstone and ochre.
    case canyon
    /// The blues of the brochure maps.
    case tidewater

    /// What a reader gets before they choose, and what a preview renders.
    public static let standard = Palette.unigrid

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .unigrid: "Unigrid"
        case .press: "Press"
        case .canyon: "Canyon"
        case .tidewater: "Tidewater"
        }
    }

    public var detail: String {
        switch self {
        case .unigrid: "Warm brochure stock and park green"
        case .press: "Ink on paper, near-monochrome"
        case .canyon: "Sandstone and ochre"
        case .tidewater: "The blues of the brochure maps"
        }
    }
}

/// Every colour one palette resolves to in one scheme.
public struct PaletteColors: Hashable, Sendable {
    /// The guide page: brochure stock.
    public let page: ColorValue
    /// Panel fill, used sparingly to group panels as the brochures do.
    public let panel: ColorValue
    /// Body text on the page.
    public let ink: ColorValue
    /// Captions, credits and data labels.
    public let inkSecondary: ColorValue
    /// Hairlines between panels and under headings.
    public let rule: ColorValue
    /// The title band.
    public let band: ColorValue
    /// The park name, reversed out of the band.
    public let bandInk: ColorValue
    /// Designation and states, beneath the park name.
    ///
    /// A resolved colour rather than `bandInk` at reduced opacity: a composited alpha
    /// cannot be measured, so an opacity here would mean the contrast suite was checking
    /// something the view does not draw.
    public let bandInkSecondary: ColorValue
    /// The app's tint, and the colour a seen or visited thing is marked in.
    public let accent: ColorValue
    /// What is legible *on* `accent`.
    ///
    /// Not always white. A dark-scheme accent has to be light enough to clear its page,
    /// which leaves white on it at roughly 2.3:1 — so in dark this is near-black.
    public let onAccent: ColorValue
    /// Trails, on map panels and in the guide.
    public let trail: ColorValue
    /// Water, on map panels and in the guide.
    public let water: ColorValue
    /// The America 250 seal's red.
    ///
    /// The same in every palette, varying only by scheme: a national commemoration is not
    /// ours to retint. A test holds that.
    public let seal: ColorValue
}

/// What the app draws in each colour, and what that use has to contrast against.
///
/// Exhaustive on purpose. `PaletteColors.pairing(for:)` switches over every case, so a new
/// colour cannot be added without answering what it is read against — the compiler asks,
/// rather than a reviewer having to notice.
public enum ColorRole: String, CaseIterable, Sendable {
    case bodyInkOnPage
    case bodyInkOnPanel
    case secondaryInkOnPage
    case secondaryInkOnPanel
    case panelHeadingRule
    case bandTitle
    case bandSubtitle
    case seenChip
    case accentOnPage
    case accentOnPanel
    case sealOnPage
    case panelEdge
}

extension PaletteColors {
    /// The pairing to check for one role.
    public func pairing(for role: ColorRole) -> ContrastPairing {
        switch role {
        case .bodyInkOnPage:
            pairing(role, ink, on: page, .bodyText)
        case .bodyInkOnPanel:
            pairing(role, ink, on: panel, .bodyText)
        case .secondaryInkOnPage:
            pairing(role, inkSecondary, on: page, .bodyText)
        case .secondaryInkOnPanel:
            pairing(role, inkSecondary, on: panel, .bodyText)
        case .panelHeadingRule:
            pairing(role, ink, on: panel, .userInterface)
        case .bandTitle:
            // 34pt bold, so large text.
            pairing(role, bandInk, on: band, .largeText)
        case .bandSubtitle:
            // 11pt, so body text however decorative the band looks.
            pairing(role, bandInkSecondary, on: band, .bodyText)
        case .seenChip:
            pairing(role, onAccent, on: accent, .bodyText)
        case .accentOnPage:
            pairing(role, accent, on: page, .userInterface)
        case .accentOnPanel:
            pairing(role, accent, on: panel, .userInterface)
        case .sealOnPage:
            pairing(role, seal, on: page, .userInterface)
        case .panelEdge:
            // A hairline carries no information on its own, and holding it to 3:1 would
            // turn the brochure's quiet panel edges into boxes.
            pairing(role, rule, on: panel, .decorative)
        }
    }

    private func pairing(
        _ role: ColorRole,
        _ foreground: ColorValue,
        on background: ColorValue,
        _ requirement: Contrast.Requirement
    ) -> ContrastPairing {
        ContrastPairing(
            name: role.rawValue,
            foreground: foreground,
            background: background,
            requirement: requirement
        )
    }
}
