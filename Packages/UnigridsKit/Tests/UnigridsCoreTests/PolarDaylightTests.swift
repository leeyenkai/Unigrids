import Foundation
import Testing
@testable import UnigridsCore

@Suite("Polar daylight")
struct PolarDaylightTests {
    /// Days between two month-days in a 365-day year, either way round.
    private func distance(_ lhs: PolarDaylight.MonthDay, _ month: Int, _ day: Int) -> Int {
        let starts = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let first = starts[lhs.month - 1] + lhs.day
        let second = starts[month - 1] + day
        let gap = abs(first - second)
        return min(gap, 365 - gap)
    }

    @Test("Longyearbyen's midnight sun and polar night fall on the published dates")
    func longyearbyen() throws {
        // Published: midnight sun 20 April to 23 August; the sun below the horizon all
        // day from 27 October to 15 February.
        let sun = try #require(PolarDaylight.midnightSun(latitude: 78.22))
        #expect(distance(sun.first, 4, 20) <= 2)
        #expect(distance(sun.last, 8, 23) <= 2)
        let night = try #require(PolarDaylight.polarNight(latitude: 78.22))
        #expect(distance(night.first, 10, 27) <= 2)
        #expect(distance(night.last, 2, 15) <= 2)
    }

    @Test("Tromsø's polar night runs over the new year")
    func tromso() throws {
        // Published: polar night 27 November to 15 January; midnight sun from 20 May.
        let night = try #require(PolarDaylight.polarNight(latitude: 69.65))
        #expect(distance(night.first, 11, 27) <= 2)
        #expect(distance(night.last, 1, 15) <= 2)
        let sun = try #require(PolarDaylight.midnightSun(latitude: 69.65))
        #expect(distance(sun.first, 5, 20) <= 2)
    }

    @Test("on the Arctic Circle the sun stays up for a few weeks and always rises")
    func arcticCircle() throws {
        let sun = try #require(PolarDaylight.midnightSun(latitude: 66.6))
        #expect(sun.first.month == 6 && sun.last.month == 7)
        #expect(PolarDaylight.polarNight(latitude: 66.6) == nil)
    }

    @Test("Jotunheimen and Yellowstone have neither")
    func southOfTheCircle() {
        #expect(PolarDaylight.midnightSun(latitude: 61.6) == nil)
        #expect(PolarDaylight.polarNight(latitude: 61.6) == nil)
        #expect(PolarDaylight.midnightSun(latitude: 44.6) == nil)
    }

    @Test("the south has its midnight sun in the southern summer")
    func southernHemisphere() throws {
        let sun = try #require(PolarDaylight.midnightSun(latitude: -78.22))
        #expect([10, 11].contains(sun.first.month))
        #expect([2, 3].contains(sun.last.month))
    }
}
