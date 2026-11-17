import Foundation
import Testing
@testable import UnigridsCore

/// Days are the place's (ADR 0012), wherever the reader is: a stop or visit in Japan,
/// stored as noon in Tokyo, falls on the previous day in New York or California.
@Suite("Days at the place, read from elsewhere")
struct PlaceDayTests {
    private let tokyo = UnigridsCalendar.gregorian(TimeZone(identifier: "Asia/Tokyo") ?? .gmt)
    private let newYork = UnigridsCalendar.gregorian(
        TimeZone(identifier: "America/New_York") ?? .gmt
    )
    private let losAngeles = UnigridsCalendar.gregorian(
        TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    )

    /// Noon on a day in Tokyo: how a date-only stop or visit there is stored.
    private func tokyoNoon(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(tokyo.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12
        )))
    }

    @Test("a trip's day-by-day puts a stop in Japan on its day there")
    func tripDays() throws {
        let fuji = UnigridsID("jp-np-fuji-hakone-izu")
        let zion = UnigridsID("np-zion")
        let zionNoon = try #require(newYork.date(from: DateComponents(
            year: 2027, month: 7, day: 19, hour: 12
        )))
        let days = try TripSchedule.days(
            stops: [(id: zion, date: zionNoon), (id: fuji, date: tokyoNoon(2027, 7, 20))],
            legs: [],
            calendar: newYork,
            calendars: [fuji: tokyo, zion: newYork]
        )
        #expect(days.count == 2)
        #expect(days.map { UnigridsCalendar.dayKey($0.day, calendar: newYork) }
            == ["2027-07-19", "2027-07-20"])
    }

    @Test("a stop in Japan exports as an all-day event on its day there")
    func calendarExport() throws {
        let event = try TripCalendar.Event(
            uid: "stop", title: "Fuji-Hakone-Izu", day: tokyoNoon(2027, 7, 20), calendar: tokyo
        )
        let text = TripCalendar.document(
            name: "Japan", events: [event], identifier: "trip", stamp: Date(), calendar: newYork
        )
        #expect(text.contains("DTSTART;VALUE=DATE:20270720"))
        #expect(text.contains("DTEND;VALUE=DATE:20270721"))
    }

    @Test("a visit in Japan on New Year's Day counts in that year, read from California")
    func statsDay() throws {
        let visit = try VisitSummary(placeID: "jp-np-shiretoko", date: tokyoNoon(2027, 1, 1))
        // Unadjusted, it is still 2026 in Los Angeles.
        #expect(losAngeles.component(.year, from: visit.date) == 2026)
        let counted = visit.onPlaceDay(tokyo, in: losAngeles)
        #expect(UnigridsCalendar.dayKey(counted.date, calendar: losAngeles) == "2027-01-01")
    }

    @Test("a place gone from the data keeps its country's zone, read from its ID")
    func goneAbroad() {
        let japan = UnigridsCalendar.gregorian(at: nil, id: "jp-np-gone")
        #expect(japan.timeZone.identifier == "Asia/Tokyo")
        let norway = UnigridsCalendar.gregorian(at: nil, id: "no-np-gone")
        #expect(norway.timeZone.identifier == "Europe/Oslo")
        #expect(UnigridsCalendar.gregorian(at: nil, id: "np-gone").timeZone == .current)
    }
}
