#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif
import SwiftUI
import Testing
import UnigridsCore
@testable import UnigridsDesign

/// The check that an icon actually exists.
///
/// SwiftUI renders an unknown `systemName` as blank space rather than failing the build,
/// so nothing except a test like this notices. `stamp` and `stamp.fill` were drawn in five
/// places and exist in no version of SF Symbols; this suite is what stops the next one.
@Suite("Icon vocabulary")
struct SymbolTests {
    private func symbolExists(_ name: String) -> Bool {
        #if canImport(AppKit)
            NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #elseif canImport(UIKit)
            UIImage(systemName: name) != nil
        #else
            true
        #endif
    }

    @Test("every symbol in the vocabulary exists", arguments: UnigridsSymbol.allCases)
    func symbolsResolve(symbol: UnigridsSymbol) {
        #expect(symbolExists(symbol.systemName), "no such SF Symbol: \(symbol.systemName)")
    }

    @Test("every place kind has a symbol that exists", arguments: PlaceKind.allCases)
    func placeSymbolsResolve(kind: PlaceKind) {
        let name = UnigridsSymbol.place(kind)
        #expect(symbolExists(name), "\(kind.rawValue): no such SF Symbol: \(name)")
    }

    @Test("a place pin is filled, because a pin is a place and not an action")
    func placeSymbolsAreFilled() {
        // The one fill rule the vocabulary follows. `sparkles` and `road.lanes` have no
        // filled variant, so they are named exceptions rather than silent ones.
        let unfillable: Set<PlaceKind> = [.naturalLandmark, .scenicByway]
        for kind in PlaceKind.allCases where !unfillable.contains(kind) {
            #expect(
                UnigridsSymbol.place(kind).hasSuffix(".fill"),
                "\(kind.rawValue) uses an outline glyph where a pin is wanted"
            )
        }
    }
}

@Suite("Style bridge")
struct StyleBridgeTests {
    @Test("a Core colour lands in the Color it was given", arguments: Palette.allCases)
    func coreColoursBridgeIntact(palette: Palette) {
        // Guards the transposition that no contrast test can see: a palette whose `page`
        // and `panel` were swapped on the way into SwiftUI still passes every ratio.
        for scheme in PaletteScheme.allCases {
            let colors = palette.colors(scheme)
            let style = UnigridStyle(palette: palette, scheme: scheme)
            #expect(style.page == Color(colors.page))
            #expect(style.panel == Color(colors.panel))
            #expect(style.ink == Color(colors.ink))
            #expect(style.band == Color(colors.band))
            #expect(style.accent == Color(colors.accent))
            #expect(style.onAccent == Color(colors.onAccent))
            #expect(style.seal == Color(colors.seal))
        }
    }

    @Test("the environment default is the app's default, not an arbitrary one")
    func fallbackMatchesDefaults() {
        #expect(UnigridStyle.fallback.palette == Palette.standard)
        #expect(UnigridStyle.fallback.scheme == .dark)
    }

    @Test("SwiftUI's scheme maps onto the palette's")
    func schemeBridge() {
        #expect(PaletteScheme(ColorScheme.dark) == .dark)
        #expect(PaletteScheme(ColorScheme.light) == .light)
    }

    @Test("a bad hex greys out at the view boundary rather than crashing")
    func hexFallback() {
        #expect(Color(hex: "nonsense") == Color.gray)
        #expect(Color(hex: "2E5339") != Color.gray)
    }

    @Test("every region ink and agency tint resolves in both schemes")
    func inksBridge() {
        for scheme in PaletteScheme.allCases {
            let style = UnigridStyle(palette: .unigrid, scheme: scheme)
            for region in PassportRegion.allCases {
                #expect(style.regionInk(region) == Color(region.ink(scheme)))
            }
        }
    }
}
