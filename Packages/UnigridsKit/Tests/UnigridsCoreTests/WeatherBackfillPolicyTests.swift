import Foundation
import Testing
import UnigridsCore

@Suite("Weather backfill policy")
struct WeatherBackfillPolicyTests {
    private let utah = UnigridsCalendar.gregorian(TimeZone(identifier: "America/Denver") ?? .gmt)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utah.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    @Test("a day still under way at the place is not asked for: it would be a forecast")
    func notToday() {
        let now = date(2026, 7, 4, hour: 20)
        #expect(!WeatherBackfillPolicy.isDue(
            date: date(2026, 7, 4, hour: 9),
            calendar: utah,
            attempt: nil,
            now: now
        ))
        #expect(WeatherBackfillPolicy.isDue(
            date: date(2026, 7, 3),
            calendar: utah,
            attempt: nil,
            now: now
        ))
    }

    @Test("a date the archive does not hold is never asked for")
    func beforeTheArchive() {
        #expect(!WeatherBackfillPolicy.isDue(date: date(1935, 6, 1), calendar: utah, attempt: nil))
    }

    @Test("a failure waits a day, and three stop the asking")
    func backoff() {
        let now = date(2026, 7, 10)
        let visit = date(2026, 6, 1)
        let recent = WeatherBackfillPolicy.Attempt(count: 1, last: now.addingTimeInterval(-3600))
        let older = WeatherBackfillPolicy.Attempt(
            count: 1,
            last: now.addingTimeInterval(-2 * 86400)
        )
        let spent = WeatherBackfillPolicy.Attempt(
            count: 3,
            last: now.addingTimeInterval(-30 * 86400)
        )
        #expect(!WeatherBackfillPolicy.isDue(
            date: visit,
            calendar: utah,
            attempt: recent,
            now: now
        ))
        #expect(WeatherBackfillPolicy.isDue(date: visit, calendar: utah, attempt: older, now: now))
        #expect(!WeatherBackfillPolicy.isDue(date: visit, calendar: utah, attempt: spent, now: now))
    }
}
