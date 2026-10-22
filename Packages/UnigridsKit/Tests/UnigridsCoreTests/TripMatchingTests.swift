import Foundation
import Testing
import UnigridsCore

@Suite("Trip matching")
struct TripMatchingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private func candidate(
        start: Date?, end: Date? = nil, status: TripStatus = .planned, lists: Bool = true
    ) -> TripMatching.Candidate {
        TripMatching.Candidate(
            id: UUID(),
            start: start,
            end: end,
            status: status,
            listsPlace: lists
        )
    }

    @Test("the dated trip covering the day wins")
    func covering() {
        let utah = candidate(start: day(5, 1), end: day(5, 6))
        let autumn = candidate(start: day(9, 1), end: day(9, 3))
        #expect(TripMatching.trip(for: day(5, 3), among: [autumn, utah], calendar: calendar) == utah
            .id)
    }

    @Test("a trip that does not list the place never takes the visit")
    func mustList() {
        let elsewhere = candidate(start: day(5, 1), end: day(5, 6), lists: false)
        #expect(TripMatching.trip(for: day(5, 3), among: [elsewhere], calendar: calendar) == nil)
    }

    @Test("two covering trips are ambiguous, so the visit stays loose")
    func ambiguous() {
        let one = candidate(start: day(5, 1), end: day(5, 6))
        let two = candidate(start: day(5, 2), end: day(5, 4))
        #expect(TripMatching.trip(for: day(5, 3), among: [one, two], calendar: calendar) == nil)
    }

    @Test("an undated trip takes a visit logged live, not a back-dated one")
    func undatedOnlyLive() {
        let someday = candidate(start: nil)
        let now = day(5, 3)
        #expect(TripMatching
            .trip(for: now, among: [someday], now: now, calendar: calendar) == someday.id)
        #expect(TripMatching.trip(
            for: day(5, 3, year: 2019), among: [someday], now: now, calendar: calendar
        ) == nil)
        let finished = candidate(start: nil, status: .done)
        #expect(TripMatching.trip(for: now, among: [finished], now: now, calendar: calendar) == nil)
    }

    @Test("a trip's status comes from its dates, or what the reader set")
    func status() {
        #expect(TripStatus.on(
            day(4, 30),
            start: day(5, 1),
            end: day(5, 6),
            stored: .done,
            calendar: calendar
        )
            == .planned)
        #expect(TripStatus.on(
            day(5, 6),
            start: day(5, 1),
            end: day(5, 6),
            stored: .planned,
            calendar: calendar
        )
            == .active)
        #expect(TripStatus.on(
            day(5, 7),
            start: day(5, 1),
            end: nil,
            stored: .planned,
            calendar: calendar
        )
            == .done)
        #expect(TripStatus
            .on(day(5, 7), start: nil, end: nil, stored: .active, calendar: calendar) == .active)
    }
}
