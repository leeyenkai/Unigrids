import Foundation
import Testing
@testable import UnigridsCore

@Suite("Stamp impressions")
struct StampImpressionTests {
    @Test("the same seed always produces the same impression")
    func impressionIsDeterministic() {
        let first = StampImpression(seed: 42)
        let second = StampImpression(seed: 42)
        #expect(first == second)
    }

    @Test("different seeds produce different impressions")
    func impressionVariesBySeed() {
        let impressions = (1 ... 50).map { StampImpression(seed: UInt64($0)) }
        #expect(Set(impressions).count == impressions.count)
    }

    @Test("an impression stays inside its visual bounds")
    func impressionStaysInBounds() {
        for seed in UInt64(0) ... 500 {
            let impression = StampImpression(seed: seed)
            #expect((-6.0 ... 6.0).contains(impression.tiltDegrees))
            #expect((-5.0 ... 5.0).contains(impression.offsetX))
            #expect((-4.0 ... 4.0).contains(impression.offsetY))
            #expect((0.78 ... 1.0).contains(impression.inkDensity))
            #expect((-14.0 ... 14.0).contains(impression.sealTiltDegrees))
        }
    }

    @Test("a zero seed is handled rather than degenerate")
    func zeroSeedIsUsable() {
        let zero = StampImpression(seed: 0)
        let one = StampImpression(seed: 1)
        #expect(zero != one)
        #expect(zero.inkDensity > 0)
    }

    @Test("the cancellation date line prints as a cancellation does")
    func dateLineFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 18
        components.hour = 12
        guard let date = calendar.date(from: components) else {
            Issue.record("could not build the date")
            return
        }
        let face = StampFace(
            siteName: "Zion National Park",
            date: date,
            stateCode: "UT",
            region: .rockyMountain,
            seed: 7,
            calendar: calendar
        )
        #expect(face.dateLine(locale: Locale(identifier: "en_US_POSIX")) == "18 OCT 2026")
        #expect(face.hasAmerica250Seal)
    }
}
