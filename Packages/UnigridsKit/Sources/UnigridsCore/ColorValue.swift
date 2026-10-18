import Foundation

/// A colour as the app stores one: an sRGB triple, and nothing more.
///
/// Colour lives here rather than in `UnigridsDesign` for the same reason `UnigridGrid`
/// does. The contrast rule in `Contrast` is load-bearing accessibility (AGENTS.md §6), and
/// a rule that cannot be tested is a rule nobody is keeping — SwiftUI's `Color` has no
/// readable components, so a palette expressed in `Color` could never be checked. The
/// design layer maps these onto `Color` and adds nothing of its own.
public struct ColorValue: Hashable, Sendable {
    /// Red, green and blue in 0...1, in the sRGB colour space.
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clampedToUnitRange
        self.green = green.clampedToUnitRange
        self.blue = blue.clampedToUnitRange
    }

    /// A colour from a six-digit sRGB hex string, with or without a leading `#`.
    ///
    /// Failable, unlike the `Color(hex:)` the design layer offers: there is one parser, and
    /// this is the layer that knows whether a string is a colour. The forgiving grey
    /// fallback belongs at the view boundary, where a wrong colour beats a crash.
    public init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The six-digit uppercase hex form, so a failing test prints a value you can look up.
    public var hex: String {
        let channel = { (value: Double) in Int((value * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    /// Relative luminance as WCAG defines it, with the sRGB gamma expansion applied first.
    ///
    /// The weights are not arbitrary: the eye is far more sensitive to green than to blue,
    /// which is why two colours of equal lightness can have very different contrast.
    public var relativeLuminance: Double {
        func expand(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * expand(red) + 0.7152 * expand(green) + 0.0722 * expand(blue)
    }

    /// Hue in degrees, 0..<360, or `nil` for a grey, which has no hue to speak of.
    ///
    /// Only the palette tests use this, to hold dark variants to being the same ink printed
    /// on dark paper rather than a different ink altogether.
    public var hueDegrees: Double? {
        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let range = highest - lowest
        guard range > 0 else { return nil }

        let sextant: Double = if highest == red {
            (green - blue) / range
        } else if highest == green {
            2 + (blue - red) / range
        } else {
            4 + (red - green) / range
        }
        let degrees = sextant * 60
        return degrees < 0 ? degrees + 360 : degrees
    }
}

extension Double {
    fileprivate var clampedToUnitRange: Double {
        min(max(self, 0), 1)
    }
}
