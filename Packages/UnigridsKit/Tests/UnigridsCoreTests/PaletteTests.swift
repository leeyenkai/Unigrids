import Foundation
import Testing
@testable import UnigridsCore

/// The suite that makes AGENTS.md §6's "check contrast in both light and dark" true.
///
/// Parameterised rather than looped, so a failure names the palette and scheme that broke
/// instead of reporting that "the contrast test failed".
@Suite("Palette contrast")
struct PaletteContrastTests {
    @Test(
        "every palette clears WCAG AA in both schemes",
        arguments: Palette.allCases, PaletteScheme.allCases
    )
    func paletteMeetsAA(palette: Palette, scheme: PaletteScheme) {
        let colors = palette.colors(scheme)
        for role in ColorRole.allCases {
            let pairing = colors.pairing(for: role)
            #expect(pairing.passes, "\(palette.rawValue)/\(scheme.rawValue) \(pairing)")
        }
    }

    @Test(
        "the accent and the seal stay findable on the native surfaces they land on",
        arguments: Palette.allCases, PaletteScheme.allCases
    )
    func accentAndSealOnNativeSurfaces(palette: Palette, scheme: PaletteScheme) {
        // The tint and the seal are drawn on map cards, list rows and stats tiles, none of
        // which the palette owns. Clearing the lightest surface of the scheme clears the
        // rest, so this is the check that actually binds.
        let colors = palette.colors(scheme)
        for surface in scheme.referenceSurfaces {
            for (name, ink) in [("accent", colors.accent), ("seal", colors.seal)] {
                let pairing = ContrastPairing(
                    name: "\(name) on \(surface.name)",
                    foreground: ink,
                    background: surface.value,
                    requirement: .userInterface
                )
                #expect(pairing.passes, "\(palette.rawValue)/\(scheme.rawValue) \(pairing)")
            }
        }
    }

    @Test(
        "a cancellation reads as text on every passport page",
        arguments: PassportRegion.allCases, PaletteScheme.allCases
    )
    func regionInkIsLegible(region: PassportRegion, scheme: PaletteScheme) {
        // The site name on a 112-point stamp sets at about 10.6 points, so this is body
        // text at 4.5:1. Treating a stamp as a graphic and settling for 3:1 is the mistake
        // that left nine inks unreadable on a dark page.
        let ink = region.ink(scheme)
        for surface in scheme.referenceSurfaces {
            let pairing = ContrastPairing(
                name: "\(region.rawValue) on \(surface.name)",
                foreground: ink,
                background: surface.value,
                requirement: .bodyText
            )
            #expect(pairing.passes, "\(scheme.rawValue) \(pairing)")
        }
    }

    @Test(
        "an agency tint is findable on a pin and in a list row",
        arguments: AgencyInk.allCases, PaletteScheme.allCases
    )
    func agencyTintIsFindable(agency: AgencyInk, scheme: PaletteScheme) {
        let ink = agency.value(scheme)
        for surface in scheme.referenceSurfaces {
            let pairing = ContrastPairing(
                name: "\(agency.rawValue) on \(surface.name)",
                foreground: ink,
                background: surface.value,
                requirement: .userInterface
            )
            #expect(pairing.passes, "\(scheme.rawValue) \(pairing)")
        }
    }
}

@Suite("Palette resolution")
struct PaletteTests {
    @Test("dark is the default appearance, and unigrid the default palette")
    func defaults() {
        #expect(AppearancePreference.standard == .dark)
        #expect(Palette.standard == .unigrid)
    }

    @Test("every palette actually differs between light and dark")
    func schemesDiffer() {
        // Catches the copy-paste where a new palette's dark column was never filled in,
        // which the contrast suite would pass in light and fail only in dark.
        for palette in Palette.allCases {
            #expect(
                palette.colors(.light) != palette.colors(.dark),
                "\(palette.rawValue) resolves identically in both schemes"
            )
        }
    }

    @Test("every palette is actually a different palette", arguments: PaletteScheme.allCases)
    func palettesDiffer(scheme: PaletteScheme) {
        let resolved = Palette.allCases.map { $0.colors(scheme) }
        #expect(Set(resolved).count == Palette.allCases.count)
    }

    @Test("the America 250 seal is the same red in every palette")
    func sealIsNotPaletteDriven() {
        // §9 makes the seal a commemoration of a specific year, not a decorative accent.
        for scheme in PaletteScheme.allCases {
            let seals = Set(Palette.allCases.map { $0.colors(scheme).seal })
            #expect(seals.count == 1, "\(scheme.rawValue) has \(seals.count) seal colours")
        }
    }

    @Test("stored raw values are a format, not an implementation detail")
    func storedRawValuesAreStable() {
        // These strings sit in UserDefaults on real devices. Renaming a case silently
        // resets everyone's choice, so the test names the cost of doing it.
        #expect(AppearancePreference.allCases.map(\.rawValue) == ["dark", "light", "system"])
        #expect(
            Palette.allCases.map(\.rawValue) == ["unigrid", "press", "canyon", "tidewater"]
        )
        #expect(AppearanceDefaults.appearance == "appearance.preference")
        #expect(AppearanceDefaults.palette == "appearance.palette")
    }

    @Test(
        "a region's dark ink is the same ink, not a different one",
        arguments: PassportRegion.allCases
    )
    func inkKeepsItsHue(region: PassportRegion) {
        // A dark variant is the region's ink printed on dark paper. Lightness is free to
        // move; hue is not, or the passport's colour-coding stops meaning anything.
        guard let light = region.ink(.light).hueDegrees,
              let dark = region.ink(.dark).hueDegrees
        else {
            Issue.record("\(region.rawValue) has a greyscale ink")
            return
        }
        let drift = abs((dark - light + 540).truncatingRemainder(dividingBy: 360) - 180)
        #expect(drift <= 12, "\(region.rawValue) hue moved \(drift)°")
    }

    @Test("an agency keeps its hue between schemes", arguments: AgencyInk.allCases)
    func agencyKeepsItsHue(agency: AgencyInk) {
        guard let light = agency.value(.light).hueDegrees,
              let dark = agency.value(.dark).hueDegrees
        else { return }
        let drift = abs((dark - light + 540).truncatingRemainder(dividingBy: 360) - 180)
        #expect(drift <= 12, "\(agency.rawValue) hue moved \(drift)°")
    }

    @Test("every agency and tier maps to an ink")
    func agencyMappingIsTotal() {
        for agency in Agency.allCases {
            for tier in PlaceTier.allCases {
                let ink = AgencyInk.forPlace(agency: agency, tier: tier)
                #expect(ink.value(.light) != ink.value(.dark))
            }
        }
        #expect(AgencyInk.forPlace(agency: .nps, tier: .nationalPark) == .nationalPark)
        #expect(AgencyInk.forPlace(agency: .nps, tier: .npsUnit) == .npsUnit)
    }
}

@Suite("Site inks")
struct SiteInkTests {
    @Test("a white pictogram reads on every pin", arguments: SiteInk.allCases)
    func pictogramReads(ink: SiteInk) {
        let pairing = ContrastPairing(
            name: "pictogram on \(ink.rawValue)",
            foreground: SiteInk.pictogram,
            background: ink.pin,
            requirement: .userInterface
        )
        #expect(pairing.passes, "\(pairing)")
    }

    @Test("the visited tick reads, white on its green")
    func visitedTickReads() {
        #expect(Contrast.meets(
            .userInterface, foreground: SiteInk.pictogram, background: SiteInk.visitedTick
        ))
    }

    @Test(
        "an outline or list tint is findable on the surfaces it lands on",
        arguments: SiteInk.allCases, PaletteScheme.allCases
    )
    func outlineIsFindable(ink: SiteInk, scheme: PaletteScheme) {
        for surface in scheme.referenceSurfaces {
            let pairing = ContrastPairing(
                name: "\(ink.rawValue) on \(surface.name)",
                foreground: ink.value(scheme),
                background: surface.value,
                requirement: .userInterface
            )
            #expect(pairing.passes, "\(scheme.rawValue) \(pairing)")
        }
    }

    @Test("a kind of place keeps its hue between schemes", arguments: SiteInk.allCases)
    func keepsItsHue(ink: SiteInk) {
        guard let light = ink.value(.light).hueDegrees,
              let dark = ink.value(.dark).hueDegrees
        else { return }
        let drift = abs((dark - light + 540).truncatingRemainder(dividingBy: 360) - 180)
        #expect(drift <= 12, "\(ink.rawValue) hue moved \(drift)°")
    }

    @Test("no two kinds of place are drawn in colours the eye would confuse")
    func pinsAreDistinct() {
        // CIE76 distance in Lab. Around 2.3 is the smallest difference anyone notices; 30
        // is two colours nobody would call the same at a glance, which is the point of
        // colouring pins by kind (they looked alike when they were all agency greens).
        for (index, one) in SiteInk.allCases.enumerated() {
            for other in SiteInk.allCases.dropFirst(index + 1) {
                let distance = one.pin.lab.distance(to: other.pin.lab)
                #expect(distance >= 30, "\(one.rawValue) and \(other.rawValue): \(distance)")
            }
        }
    }

    @Test("every site type has an ink, and every ink is used")
    func mappingIsTotal() {
        let used = Set(SiteType.allCases.map(\.ink))
        #expect(used == Set(SiteInk.allCases))
        #expect(SiteType.battlefield.ink == SiteType.historicSite.ink)
        #expect(SiteType.nationalForest.ink != SiteType.nationalPark.ink)
    }
}

/// CIE L*a*b* under D65, for the distinctness test.
private struct LabColour {
    let lightness: Double
    let greenRed: Double
    let blueYellow: Double

    func distance(to other: LabColour) -> Double {
        let lightnessGap = lightness - other.lightness
        let redGap = greenRed - other.greenRed
        let yellowGap = blueYellow - other.blueYellow
        return (lightnessGap * lightnessGap + redGap * redGap + yellowGap * yellowGap)
            .squareRoot()
    }
}

extension ColorValue {
    fileprivate var lab: LabColour {
        func expand(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let red = expand(red)
        let green = expand(green)
        let blue = expand(blue)
        let xRatio = (0.4124 * red + 0.3576 * green + 0.1805 * blue) / 0.950_47
        let yRatio = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let zRatio = (0.0193 * red + 0.1192 * green + 0.9505 * blue) / 1.088_83
        func pivot(_ value: Double) -> Double {
            value > 0.008_856 ? pow(value, 1.0 / 3) : 7.787 * value + 16.0 / 116
        }
        return LabColour(
            lightness: 116 * pivot(yRatio) - 16,
            greenRed: 500 * (pivot(xRatio) - pivot(yRatio)),
            blueYellow: 200 * (pivot(yRatio) - pivot(zRatio))
        )
    }
}
