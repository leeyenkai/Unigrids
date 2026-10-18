import SwiftUI
import UnigridsCore

/// The Unigrid design language, used by park guides and nothing else.
///
/// The app has two visual modes (SPECIFICATION.md §14): guides speak Unigrid, and the
/// map, trips, passport, stats and settings use the current native Apple design so the
/// app feels at home on each device. Keeping the two apart is deliberate — reach for
/// `UnigridStyle` only inside a guide.
///
/// The reference is the 1977 system Massimo Vignelli's office designed for the NPS: a
/// modular grid of fold panels, a black title band across the top, and Helvetica paired
/// with Times Roman. This is homage, not reproduction.
///
/// An instance is one palette resolved for one colour scheme. Views read it from the
/// environment — `@Environment(\.unigrid) private var style` — rather than passing a
/// `ColorScheme` into a function, so resolution happens once at the scene root and a panel
/// cannot disagree with the page it sits on. Fonts and metrics stay `static`: they do not
/// vary by palette, and making them instance members would have churned every call site
/// for nothing.
public struct UnigridStyle: Equatable, Sendable {
    public let palette: Palette
    public let scheme: PaletteScheme

    // MARK: - Colour

    /// The guide page. Brochure stock.
    public let page: Color
    /// Panel fill, used sparingly to group panels as the brochures do.
    public let panel: Color
    /// Body text on the page.
    public let ink: Color
    /// Secondary text: captions, credits, data labels.
    public let inkSecondary: Color
    /// Hairlines between panels and under headings.
    public let rule: Color
    /// The title band.
    public let band: Color
    /// The park name, reversed out of the band.
    public let bandInk: Color
    /// Designation and states, beneath the park name.
    public let bandInkSecondary: Color
    /// The app's tint, and the mark on anything seen or visited.
    public let accent: Color
    /// What is legible on `accent` — not always white. See `PaletteColors.onAccent`.
    public let onAccent: Color
    /// The NPS cartographic browns and blues, for map panels and accents.
    public let trail: Color
    public let water: Color
    /// The America 250 seal's red.
    public let seal: Color

    public init(palette: Palette, scheme: PaletteScheme) {
        let colors = palette.colors(scheme)
        self.palette = palette
        self.scheme = scheme
        page = Color(colors.page)
        panel = Color(colors.panel)
        ink = Color(colors.ink)
        inkSecondary = Color(colors.inkSecondary)
        rule = Color(colors.rule)
        band = Color(colors.band)
        bandInk = Color(colors.bandInk)
        bandInkSecondary = Color(colors.bandInkSecondary)
        accent = Color(colors.accent)
        onAccent = Color(colors.onAccent)
        trail = Color(colors.trail)
        water = Color(colors.water)
        seal = Color(colors.seal)
    }

    /// The environment's default, and what a preview gets for free.
    ///
    /// Dark, because that is the app's default appearance: a preview that silently renders
    /// the non-default is a trap.
    public static let fallback = UnigridStyle(palette: .standard, scheme: .dark)

    /// A region's cancellation ink in this scheme.
    ///
    /// Stamps land on native passport pages, not on Unigrid paper, so this and `seal` are
    /// the only members a stamp may read.
    public func regionInk(_ region: PassportRegion) -> Color {
        Color(region.ink(scheme))
    }

    /// The pin and row colour for a place, by the agency behind it.
    public func agencyTint(for place: Place) -> Color {
        Color(AgencyInk.forPlace(agency: place.agency, tier: place.tier).value(scheme))
    }

    // MARK: - Type

    //
    // The original pairing was Helvetica with Times Roman. Helvetica Neue ships on every
    // Apple platform, so headings and data use it by name; longer passages use the
    // system serif, which is a closer match to how a reader expects body text to behave
    // with Dynamic Type than a named Times would be.

    public static func bandTitle(_ size: CGFloat = 34) -> Font {
        .custom("HelveticaNeue-Bold", size: size, relativeTo: .largeTitle)
    }

    public static var panelHeading: Font {
        .custom("HelveticaNeue-Bold", size: 13, relativeTo: .subheadline)
    }

    public static var dataLabel: Font {
        .custom("HelveticaNeue-Medium", size: 11, relativeTo: .caption)
    }

    public static var dataValue: Font {
        .custom("HelveticaNeue", size: 15, relativeTo: .body)
    }

    public static var itemTitle: Font {
        .custom("HelveticaNeue-Medium", size: 16, relativeTo: .headline)
    }

    /// Longer passages: the story, safety notes, chronology entries.
    public static var prose: Font {
        .system(.body, design: .serif)
    }

    public static var caption: Font {
        .custom("HelveticaNeue", size: 11, relativeTo: .caption2)
    }

    // MARK: - Metrics

    /// The gap between panels, from the brochure's own module.
    public static let gutter: CGFloat = 16
    public static let panelPadding: CGFloat = 18
    public static let pageMargin: CGFloat = 16

    /// Maps the reader's text size onto the scale `UnigridGrid` uses to decide how many
    /// columns fit. Each step up the accessibility sizes takes a column away sooner.
    public static func typeScale(for size: DynamicTypeSize) -> Double {
        switch size {
        case .xSmall, .small, .medium, .large: 1.0
        case .xLarge: 1.15
        case .xxLarge: 1.3
        case .xxxLarge: 1.45
        case .accessibility1: 1.7
        case .accessibility2: 2.0
        case .accessibility3: 2.3
        case .accessibility4: 2.6
        case .accessibility5: 3.0
        @unknown default: 1.0
        }
    }
}

/// Corner radii and insets for the native side of the app.
///
/// Native screens keep Apple's semantic colours and fonts, but the radii were previously
/// inline magic numbers that drifted between screens. One scale, named, so a tile and a
/// card agree without anyone having to remember a number.
public enum NativeMetrics {
    /// Stat tiles and cards.
    public static let cardRadius: CGFloat = 14
    /// Thumbnails, chips and smaller inset surfaces.
    public static let chipRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 14
    public static let rowSpacing: CGFloat = 12
}

extension PaletteScheme {
    /// SwiftUI's scheme, mapped onto the Foundation one the palette is defined in.
    public init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

extension Color {
    /// A colour resolved from `UnigridsCore`.
    public init(_ value: ColorValue) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
    }

    /// A colour from a six-digit sRGB hex string. Unparseable input falls back to grey
    /// rather than crashing, because a wrong colour is a visual bug and a crash is not.
    public init(hex: String) {
        self = ColorValue(hex: hex).map(Color.init) ?? .gray
    }
}
