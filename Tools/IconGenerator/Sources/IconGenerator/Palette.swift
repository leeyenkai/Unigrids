import CoreGraphics

/// A flat ink.
///
/// The icon is printed, not lit: there is no gradient anywhere in it, so a colour is
/// three numbers and nothing else.
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
    /// The top cover.
    let paperFront: Ink
    /// The covers under it.
    let paperBack: Ink
    /// The cut edge of the paper, towards the viewer, and the one in shade to the right.
    let edge: Ink
    let edgeShadow: Ink
    /// The black band across the head of the cover.
    let band: Ink
    /// A rule of set type on the cover.
    let textBlock: Ink
    /// The one block in colour.
    let accent: Ink
    /// How far the frost tints what is behind it towards the paper's own white.
    let frostAlpha: CGFloat
    /// How brightly the lit edge of a sheet catches the light.
    let rimAlpha: CGFloat
}

extension Palette {
    /// The brochure in daylight.
    static let light = Palette(
        paperFront: Ink(hex: 0xFFFFFF),
        paperBack: Ink(hex: 0xF3EFE7),
        edge: Ink(hex: 0xDED8CC),
        edgeShadow: Ink(hex: 0xBFB8A9),
        band: Ink(hex: 0x121212),
        textBlock: Ink(hex: 0xA8A49B),
        accent: Ink(hex: 0x2E5339),
        frostAlpha: 0.34,
        rimAlpha: 0.72
    )

    /// The brochure after dark. Zion and Yosemite are both dark-sky parks, so the dark
    /// variant is not an inversion — it is night, and the rock keeps its hue.
    static let dark = Palette(
        paperFront: Ink(hex: 0x3E434D),
        paperBack: Ink(hex: 0x343841),
        edge: Ink(hex: 0x2A2E35),
        edgeShadow: Ink(hex: 0x1F2228),
        band: Ink(hex: 0x0A0B0D),
        textBlock: Ink(hex: 0x615F5A),
        // Muted for night. The daylight green is the brightest thing in the dark
        // variant otherwise, and the eye goes to the map panel instead of the park.
        accent: Ink(hex: 0x2E5740),
        frostAlpha: 0.30,
        rimAlpha: 0.40
    )

    /// Greyscale, for the system to tint.
    static let tinted = Palette(
        paperFront: Ink(hex: 0xF2F2F2),
        paperBack: Ink(hex: 0xDCDCDC),
        edge: Ink(hex: 0xC2C2C2),
        edgeShadow: Ink(hex: 0x9E9E9E),
        band: Ink(hex: 0x0D0D0D),
        textBlock: Ink(hex: 0x8A8A8A),
        accent: Ink(hex: 0x5E5E5E),
        frostAlpha: 0.40,
        rimAlpha: 0.80
    )
}
