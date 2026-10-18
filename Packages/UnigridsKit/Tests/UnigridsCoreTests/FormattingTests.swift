import Foundation
import Testing
@testable import UnigridsCore

@Suite("Formatting")
struct FormattingTests {
    private let metric = Locale(identifier: "en_GB")
    private let imperial = Locale(identifier: "en_US")

    @Test("the UK counts as metric, not imperial")
    func unitedKingdomIsMetric() {
        // `Locale.MeasurementSystem` has three cases and the UK reports `.uk`, so a
        // `== .metric` test silently gives British readers park elevations in feet.
        #expect(!UnigridsFormat.usesUSUnits(Locale(identifier: "en_GB")))
        #expect(!UnigridsFormat.usesUSUnits(Locale(identifier: "de_DE")))
        #expect(UnigridsFormat.usesUSUnits(Locale(identifier: "en_US")))
    }

    @Test("area reads in whole units, not to the micron")
    func areaHasNoSpuriousPrecision() {
        // Acadia: 49,075 acres. Converting to hectares otherwise yields
        // "19,859.947893 ha", which claims a precision the source never had.
        let hectares = UnigridsFormat.area(acres: 49075, locale: metric)
        #expect(!hectares.contains("."), "\(hectares)")
        #expect(hectares.contains("19,860"), "\(hectares)")

        let acres = UnigridsFormat.area(acres: 49075, locale: imperial)
        #expect(!acres.contains("."), "\(acres)")
    }

    @Test("elevation ranges read as a range, and a single figure as one")
    func elevationRanges() throws {
        let range = try #require(
            UnigridsFormat.elevationRange(lowest: 1117, highest: 2660, locale: metric)
        )
        #expect(range.contains("–"))
        #expect(range.hasSuffix("m"))

        let single = UnigridsFormat.elevationRange(lowest: nil, highest: 466, locale: metric)
        #expect(single?.contains("–") == false)

        #expect(UnigridsFormat.elevationRange(lowest: nil, highest: nil) == nil)
    }

    @Test("elevation has no fractional part")
    func elevationIsWhole() {
        let feet = UnigridsFormat.elevation(2660, locale: imperial)
        #expect(!feet.contains("."), "\(feet)")
    }

    @Test("visitation reads in millions once it passes one")
    func visitorFigures() {
        #expect(UnigridsFormat.visitors(13_300_000, locale: imperial) == "13 million")
        #expect(UnigridsFormat.visitors(4_600_000, locale: imperial) == "4.6 million")
        #expect(UnigridsFormat.visitors(812_000, locale: imperial) == "812,000")
    }

    @Test("Everests are counted from sea level to the summit")
    func everests() {
        #expect(UnigridsFormat.everestMetres == 8848)
        #expect(UnigridsFormat.everests(gainMetres: 8848, locale: imperial) == "1.00")
        #expect(UnigridsFormat.everests(gainMetres: 4424, locale: imperial) == "0.50")
    }
}
