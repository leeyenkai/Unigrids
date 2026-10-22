import Foundation

/// Which logged visits are owed a weather snapshot, and when to ask again
/// (SPECIFICATION.md §11: weather is fetched once per visit and kept).
///
/// A rule rather than a loop's inline checks because it was wrong in three ways that are
/// worth a test each: it stored the forecast for a day still under way as that day's
/// weather; it retried visits that could never resolve on every launch, ahead of older
/// ones that could; and it asked the archive for dates it does not hold.
public enum WeatherBackfillPolicy {
    /// The archive (ERA5) begins in 1940.
    public static let earliest = DateComponents(
        calendar: UnigridsCalendar.gregorian(.gmt),
        year: 1940,
        month: 1,
        day: 1
    )
    .date ?? .distantPast

    /// Failures after which a visit is left alone.
    public static let maxAttempts = 3

    /// How long to wait after a failure before asking again.
    public static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        Double(attempts) * 86400
    }

    public struct Attempt: Codable, Hashable, Sendable {
        public var count: Int
        public var last: Date

        public init(count: Int, last: Date) {
            self.count = count
            self.last = last
        }
    }

    /// Whether a visit on `date`, at a place reckoned in `calendar`, should be asked for
    /// now. The day must be over there: until then the only figures are a forecast.
    public static func isDue(
        date: Date,
        calendar: Calendar,
        attempt: Attempt?,
        now: Date = Date()
    ) -> Bool {
        guard date >= earliest,
              UnigridsCalendar.dayKey(date, calendar: calendar)
              < UnigridsCalendar.dayKey(now, calendar: calendar)
        else { return false }
        guard let attempt else { return true }
        return attempt.count < maxAttempts
            && now.timeIntervalSince(attempt.last) >= backoff(afterAttempts: attempt.count)
    }
}
