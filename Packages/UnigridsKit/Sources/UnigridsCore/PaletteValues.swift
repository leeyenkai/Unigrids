import Foundation

// The palettes themselves, kept apart from the types in `Palette.swift` because a table of
// hexes and a set of rules read very differently and change for different reasons.
//
// Every value here is held by `PaletteContrastTests`. The dark sets are not eyeballed: each
// is the light ink's own hue, lifted in lightness until it clears WCAG AA against the
// *lightest* surface of its scheme. That is why a dark accent looks lighter than feels
// natural — it has to survive a grouped list background, not just the guide page.

extension Palette {
    public func colors(_ scheme: PaletteScheme) -> PaletteColors {
        switch scheme {
        case .light: lightColors
        case .dark: darkColors
        }
    }

    private var lightColors: PaletteColors {
        switch self {
        case .unigrid:
            PaletteColors(
                page: .hex("FAF8F4"), panel: .hex("FFFFFF"),
                ink: .hex("1A1A1A"), inkSecondary: .hex("5E5A52"),
                rule: .hex("D8D3C9"),
                band: .hex("121212"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C9C6C0"),
                accent: .hex("2E5339"), onAccent: .hex("FFFFFF"),
                trail: .hex("7A5A3C"), water: .hex("3C6E8F"),
                seal: .sealLight
            )
        case .press:
            PaletteColors(
                page: .hex("F7F6F3"), panel: .hex("FFFFFF"),
                ink: .hex("141414"), inkSecondary: .hex("56534E"),
                rule: .hex("D5D2CB"),
                band: .hex("0A0A0A"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C6C4C0"),
                accent: .hex("2B2B2B"), onAccent: .hex("FFFFFF"),
                trail: .hex("5F5A52"), water: .hex("55595E"),
                seal: .sealLight
            )
        case .canyon:
            PaletteColors(
                page: .hex("FAF4EA"), panel: .hex("FFFDF9"),
                ink: .hex("1E1813"), inkSecondary: .hex("6B5B47"),
                rule: .hex("E0D4BF"),
                band: .hex("151210"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C9C4BC"),
                accent: .hex("9A4A1B"), onAccent: .hex("FFFFFF"),
                trail: .hex("7A5A3C"), water: .hex("3C6E8F"),
                seal: .sealLight
            )
        case .tidewater:
            PaletteColors(
                page: .hex("F3F6F8"), panel: .hex("FFFFFF"),
                ink: .hex("141A1E"), inkSecondary: .hex("4F5C66"),
                rule: .hex("CBD6DE"),
                band: .hex("101416"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C2CAD0"),
                accent: .hex("1F5A7A"), onAccent: .hex("FFFFFF"),
                trail: .hex("7A5A3C"), water: .hex("3C6E8F"),
                seal: .sealLight
            )
        }
    }

    private var darkColors: PaletteColors {
        switch self {
        case .unigrid:
            PaletteColors(
                page: .hex("16171A"), panel: .hex("22252B"),
                ink: .hex("ECE9E3"), inkSecondary: .hex("A6A29A"),
                rule: .hex("3A3C42"),
                band: .hex("0E0F11"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C9C6C0"),
                accent: .hex("4C8A5F"), onAccent: .onAccentDark,
                trail: .hex("9E754E"), water: .hex("4783AA"),
                seal: .sealDark
            )
        case .press:
            // The one palette whose accent inverts between schemes, and correctly so: in
            // a monochrome scheme the ink *is* the accent, and ink on dark paper is light.
            PaletteColors(
                page: .hex("141414"), panel: .hex("1F1F1F"),
                ink: .hex("EDEBE7"), inkSecondary: .hex("A3A09A"),
                rule: .hex("3A3A3A"),
                band: .hex("080808"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C6C4C0"),
                accent: .hex("C8C5BE"), onAccent: .onAccentDark,
                trail: .hex("9A948B"), water: .hex("959CA3"),
                seal: .sealDark
            )
        case .canyon:
            PaletteColors(
                page: .hex("17140F"), panel: .hex("23201A"),
                ink: .hex("EFE9DF"), inkSecondary: .hex("A9A194"),
                rule: .hex("3E3A32"),
                band: .hex("100E0C"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C9C4BC"),
                accent: .hex("D07A3E"), onAccent: .onAccentDark,
                trail: .hex("9E754E"), water: .hex("4783AA"),
                seal: .sealDark
            )
        case .tidewater:
            PaletteColors(
                page: .hex("10161A"), panel: .hex("1B2429"),
                ink: .hex("E6EDF2"), inkSecondary: .hex("9CAAB4"),
                rule: .hex("334049"),
                band: .hex("0B0F12"), bandInk: .hex("FFFFFF"),
                bandInkSecondary: .hex("C2CAD0"),
                accent: .hex("57A3C9"), onAccent: .onAccentDark,
                trail: .hex("9E754E"), water: .hex("4783AA"),
                seal: .sealDark
            )
        }
    }
}

extension ColorValue {
    /// A compile-time palette constant.
    ///
    /// The hexes in this file are literals the tests pin, so a typo is a failing test
    /// rather than a crash; black is a visible, harmless stand-in if one ever slips past.
    fileprivate static func hex(_ value: String) -> ColorValue {
        ColorValue(hex: value) ?? ColorValue(red: 0, green: 0, blue: 0)
    }

    /// The America 250 seal, shared by every palette.
    fileprivate static let sealLight = ColorValue.hex("B3242B")
    fileprivate static let sealDark = ColorValue.hex("DB4A51")

    /// What reverses out of a dark-scheme accent.
    fileprivate static let onAccentDark = ColorValue.hex("121212")
}
