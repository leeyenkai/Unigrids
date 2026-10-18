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
public enum UnigridStyle {
    // MARK: - Colour

    /// The title band. Near-black rather than pure black, which reads as ink rather than
    /// as a hole in the page.
    public static let band = Color(hex: "121212")

    /// The guide page. Warm off-white, like coated brochure stock.
    public static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "16171A") : Color(hex: "FAF8F4")
    }

    /// Body text on the page.
    public static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "ECE9E3") : Color(hex: "1A1A1A")
    }

    /// Secondary text: captions, credits, data labels.
    public static func inkSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "A6A29A") : Color(hex: "5E5A52")
    }

    /// Panel fill, used sparingly to group panels as the brochures do.
    public static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1F2126") : Color(hex: "FFFFFF")
    }

    /// Hairlines between panels and under headings.
    public static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "3A3C42") : Color(hex: "D8D3C9")
    }

    /// The NPS cartographic greens and browns, for map panels and accents.
    public static let parkGreen = Color(hex: "2E5339")
    public static let trailBrown = Color(hex: "7A5A3C")
    public static let waterBlue = Color(hex: "3C6E8F")
    /// The America 250 seal's red.
    public static let sealRed = Color(hex: "B3242B")

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

extension Color {
    /// A colour from a six-digit sRGB hex string. Unparseable input falls back to grey
    /// rather than crashing, because a wrong colour is a visual bug and a crash is not.
    public init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension PassportRegion {
    /// The region's cancellation ink.
    public var inkColor: Color {
        Color(hex: inkHex)
    }
}
