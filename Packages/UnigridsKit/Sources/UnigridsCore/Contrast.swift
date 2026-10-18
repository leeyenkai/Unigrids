import Foundation

/// The contrast rule, as a pure function over colour values.
///
/// AGENTS.md §6 asks for contrast "checked in both light and dark". This is the thing that
/// checks it. It lives in `UnigridsCore` beside `UnigridGrid`, the app's other load-bearing
/// accessibility rule, so both are arithmetic a test can reach without a view.
public enum Contrast {
    /// What a pairing has to clear, decided by what it is used for.
    ///
    /// The thresholds are WCAG 2.2 AA. Large text means 18pt, or 14pt bold — note that a
    /// caption inside a graphic is still body text, however graphical the graphic is.
    public enum Requirement: String, CaseIterable, Sendable {
        /// Body copy, labels, captions: anything below 18pt, or below 14pt bold.
        case bodyText
        /// Headings at 18pt or more, or 14pt bold and up.
        case largeText
        /// Icons, strokes and controls the reader has to find.
        case userInterface
        /// Hairlines and fills that carry no information alone, exempt under WCAG 1.4.11.
        ///
        /// Listed rather than omitted on purpose: a new colour has to say it is decorative
        /// to escape the check, which is a decision someone makes rather than an omission
        /// nobody notices.
        case decorative

        public var minimumRatio: Double {
            switch self {
            case .bodyText: 4.5
            case .largeText, .userInterface: 3
            case .decorative: 1
            }
        }
    }

    /// The WCAG contrast ratio between two colours, from 1 to 21.
    ///
    /// Symmetric: which colour is the foreground makes no difference to the number.
    public static func ratio(_ one: ColorValue, _ other: ColorValue) -> Double {
        let lighter = max(one.relativeLuminance, other.relativeLuminance)
        let darker = min(one.relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func meets(
        _ requirement: Requirement,
        foreground: ColorValue,
        background: ColorValue
    ) -> Bool {
        ratio(foreground, background) >= requirement.minimumRatio
    }
}

/// One foreground drawn on one background, with the threshold that applies to it.
///
/// A named value rather than a loose tuple so a failing test says which pairing broke, in
/// which palette, and by how much — enough to fix it without re-deriving anything.
public struct ContrastPairing: Hashable, Sendable, CustomStringConvertible {
    public let name: String
    public let foreground: ColorValue
    public let background: ColorValue
    public let requirement: Contrast.Requirement

    public init(
        name: String,
        foreground: ColorValue,
        background: ColorValue,
        requirement: Contrast.Requirement
    ) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.requirement = requirement
    }

    public var ratio: Double {
        Contrast.ratio(foreground, background)
    }

    public var passes: Bool {
        ratio >= requirement.minimumRatio
    }

    public var description: String {
        let measured = String(format: "%.2f", ratio)
        let needed = String(format: "%.1f", requirement.minimumRatio)
        return "\(name): \(foreground.hex) on \(background.hex) is \(measured):1, needs \(needed):1"
    }
}
