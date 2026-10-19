import CoreGraphics

/// One colour, as three numbers in sRGB.
struct Ink {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }
}

/// The inks one variant of the icon is printed in.
///
/// Values are the app's own palette where the app has one, written out here rather than
/// imported: `Tools/` must not depend on `UnigridsKit`, and an icon that silently changed
/// when the palette was refactored would be worse than a duplicated constant. Kept in
/// step with `Packages/UnigridsKit/Sources/UnigridsCore/PaletteValues.swift` by hand.
struct Palette {
    /// The paper the covers are printed on, and the ink the band's lettering is set in.
    let paperFront: Ink
    /// The black band across the head of the cover.
    let band: Ink
    /// A rule of set type on the cover.
    let textBlock: Ink
    /// The one block in colour.
    let accent: Ink
    /// How far the frost tints what is behind it towards the paper's own white.
    let frostAlpha: CGFloat
}

extension Palette {
    /// The brochure in daylight.
    static let light = Palette(
        paperFront: Ink(hex: 0xFFFFFF),
        band: Ink(hex: 0x121212),
        textBlock: Ink(hex: 0xA8A49B),
        accent: Ink(hex: 0x2E5339),
        frostAlpha: 0.34
    )

    /// The brochure after dark. Not an inversion: it is night in the park, and the rock
    /// keeps its hue.
    static let dark = Palette(
        paperFront: Ink(hex: 0x3E434D),
        band: Ink(hex: 0x0A0B0D),
        textBlock: Ink(hex: 0x615F5A),
        // Muted for night. The daylight green is the brightest thing in the dark
        // variant otherwise, and the eye goes to the map panel instead of the park.
        accent: Ink(hex: 0x2E5740),
        frostAlpha: 0.30
    )

    /// Greyscale, for the system to tint.
    static let tinted = Palette(
        paperFront: Ink(hex: 0xF2F2F2),
        band: Ink(hex: 0x0D0D0D),
        textBlock: Ink(hex: 0x8A8A8A),
        accent: Ink(hex: 0x5E5E5E),
        frostAlpha: 0.40
    )
}
