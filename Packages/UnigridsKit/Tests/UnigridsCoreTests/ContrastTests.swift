import Testing
@testable import UnigridsCore

/// A colour from a hex literal, for tests only.
///
/// `ColorValue(hex:)` is failable and force unwrapping is banned (AGENTS.md §3), so a typo
/// in a test literal shows up as an assertion about black rather than as a crash that
/// takes the whole suite with it.
func rgb(_ hex: String) -> ColorValue {
    ColorValue(hex: hex) ?? ColorValue(red: 0, green: 0, blue: 0)
}

@Suite("WCAG contrast")
struct ContrastTests {
    @Test("the ratio matches the published extremes")
    func knownRatios() {
        #expect(abs(Contrast.ratio(rgb("000000"), rgb("FFFFFF")) - 21) < 0.01)
        #expect(abs(Contrast.ratio(rgb("FFFFFF"), rgb("FFFFFF")) - 1) < 0.001)
    }

    @Test("the canonical AA boundary grey lands either side of 4.5")
    func boundaryGrey() {
        /// #767676 on white is the worked example AA is usually taught with: it clears body
        /// text by a hair and #777777 does not. A formula that gets both of these right has
        /// its gamma expansion and its 0.05 offset correct, which eyeballing cannot tell.
        func onWhite(_ hex: String) -> Double {
            Contrast.ratio(rgb(hex), rgb("FFFFFF"))
        }
        #expect(onWhite("767676") >= 4.5)
        #expect(onWhite("777777") < 4.5)
    }

    @Test("the ratio does not care which colour you call the foreground")
    func symmetry() {
        let one = rgb("2E5339")
        let other = rgb("FAF8F4")
        #expect(Contrast.ratio(one, other) == Contrast.ratio(other, one))
    }

    @Test("the thresholds are the ones WCAG AA sets")
    func thresholds() {
        #expect(Contrast.Requirement.bodyText.minimumRatio == 4.5)
        #expect(Contrast.Requirement.largeText.minimumRatio == 3)
        #expect(Contrast.Requirement.userInterface.minimumRatio == 3)
        #expect(Contrast.Requirement.decorative.minimumRatio == 1)
    }

    @Test("a hex round-trips, and junk is rejected rather than guessed at")
    func hexParsing() {
        #expect(rgb("2E5339").hex == "2E5339")
        #expect(ColorValue(hex: "#2E5339") == ColorValue(hex: "2E5339"))
        #expect(ColorValue(hex: "nope") == nil)
        #expect(ColorValue(hex: "2E53") == nil)
        #expect(ColorValue(hex: "") == nil)
    }

    @Test("luminance is ordered the way the eye orders it")
    func luminanceOrdering() {
        // Green carries far more luminance than blue at the same channel value. A palette
        // author who assumes otherwise picks accents that fail only in one scheme.
        #expect(rgb("00FF00").relativeLuminance > rgb("FF0000").relativeLuminance)
        #expect(rgb("FF0000").relativeLuminance > rgb("0000FF").relativeLuminance)
    }

    @Test("a grey reports no hue, and a colour reports the hue it looks")
    func hue() {
        #expect(rgb("808080").hueDegrees == nil)
        #expect(rgb("FFFFFF").hueDegrees == nil)
        let red = rgb("FF0000").hueDegrees ?? -1
        let green = rgb("00FF00").hueDegrees ?? -1
        let blue = rgb("0000FF").hueDegrees ?? -1
        #expect(abs(red) < 0.5)
        #expect(abs(green - 120) < 0.5)
        #expect(abs(blue - 240) < 0.5)
    }
}
