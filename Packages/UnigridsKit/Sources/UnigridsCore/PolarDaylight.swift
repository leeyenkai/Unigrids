import Foundation

/// Midnight sun and polar night at a latitude: the stretches of the year when the sun
/// stays above the horizon all day, or below it all day (SPECIFICATION.md §6).
///
/// Worked out, not looked up: the sun's declination for each day of the year, from NOAA's
/// Fourier series (good to about 0.05°), against the latitude, with the 0.833° below the
/// horizon that sunrise tables use for refraction and the sun's half-width. The dates fall
/// within a day or two of published tables, so the screens say "about".
public enum PolarDaylight {
    /// A day of the year, as a month and a day.
    public struct MonthDay: Hashable, Sendable {
        public let month: Int
        public let day: Int
    }

    /// The first and last day of a stretch. A polar night runs over the new year, so its
    /// first day falls later in the calendar than its last.
    public struct Period: Hashable, Sendable {
        public let first: MonthDay
        public let last: MonthDay
    }

    /// The days the sun never sets, or nil south of about 65.7°N (north of 65.7°S).
    public static func midnightSun(latitude: Double) -> Period? {
        period { declination in
            90 - abs(latitude) - horizon < hemisphereDeclination(declination, latitude)
        }
    }

    /// The days the sun never rises, or nil south of about 67.4°N (north of 67.4°S).
    public static func polarNight(latitude: Double) -> Period? {
        period { declination in
            hemisphereDeclination(declination, latitude) < abs(latitude) - 90 - horizon
        }
    }

    /// The sun's centre this far below the horizon is sunrise or sunset, as tables count it.
    private static let horizon = 0.833

    /// The declination as seen from the latitude's own hemisphere: June's sun is high in
    /// the north and low in the south.
    private static func hemisphereDeclination(_ value: Double, _ latitude: Double) -> Double {
        latitude < 0 ? -value : value
    }

    /// The sun's declination in degrees at noon on a day of a 365-day year (NOAA).
    static func declination(dayOfYear: Int) -> Double {
        let gamma = 2 * Double.pi / 365 * (Double(dayOfYear) - 0.5)
        let radians = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        return radians * 180 / Double.pi
    }

    /// The one run of days on which `holds` is true, joined across the new year.
    private static func period(where holds: (Double) -> Bool) -> Period? {
        let days = (1 ... 365).map { holds(declination(dayOfYear: $0)) }
        guard days.contains(true), days.contains(false) else { return nil }
        // A run starts on a day that holds after one that does not, and ends on a day
        // that holds before one that does not; the index wraps for polar night.
        guard let start = days.indices.first(where: { days[$0] && !days[($0 + 364) % 365] }),
              let end = days.indices.first(where: { days[$0] && !days[($0 + 1) % 365] })
        else { return nil }
        return Period(first: monthDay(start + 1), last: monthDay(end + 1))
    }

    private static func monthDay(_ dayOfYear: Int) -> MonthDay {
        let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var remaining = dayOfYear
        for (index, length) in lengths.enumerated() {
            if remaining <= length {
                return MonthDay(month: index + 1, day: remaining)
            }
            remaining -= length
        }
        return MonthDay(month: 12, day: 31)
    }
}
