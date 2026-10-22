import Foundation

/// The calendar every day-based rule in the app reckons with.
///
/// Two things went wrong when the rules used `Calendar.current`. On a phone set to the
/// Buddhist or Japanese calendar the year is 2569 or 8, so the America 250 seal never
/// applied and weather was asked for days that do not exist. And a date's day moved with
/// the device: a stamp at 00:30 on New Year's Day in New York lost its seal on a Mac set to
/// Pacific time.
///
/// So the rules use a Gregorian calendar with a fixed locale, in an explicit time zone —
/// a place's own wherever the question is "which day was this, there" — and a date-only
/// entry is stored as noon in that zone, which reads as the same day anywhere within
/// twelve hours of it.
public enum UnigridsCalendar {
    /// A Gregorian calendar in `timeZone`, independent of the user's region settings.
    public static func gregorian(_ timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    /// The calendar for days at `place`: its own time zone, else its state's, else the
    /// device's.
    public static func gregorian(at place: Place?) -> Calendar {
        gregorian(timeZone(for: place))
    }

    /// The time zone a place keeps.
    public static func timeZone(for place: Place?) -> TimeZone {
        guard let place else { return .current }
        return place.timeZoneID.flatMap(TimeZone.init(identifier:))
            ?? place.states.first.flatMap(\.mainTimeZone)
            ?? .current
    }

    /// `2026-07-04`: the calendar day `date` falls on in `calendar`.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 1970,
            parts.month ?? 1,
            parts.day ?? 1
        )
    }

    /// Noon, in `calendar`'s time zone, on the day `date` shows as in `shownIn`.
    ///
    /// A date picker hands back the chosen day at the current clock time in the device's
    /// zone. Re-expressing that day as noon in the place's zone means the record says the
    /// day the user picked wherever it is read later.
    public static func noon(onDayOf date: Date, shownIn: Calendar, in calendar: Calendar) -> Date {
        var parts = shownIn.dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts) ?? date
    }

    /// Whether two dates fall on one calendar day in `calendar`.
    public static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        dayKey(lhs, calendar: calendar) == dayKey(rhs, calendar: calendar)
    }
}

extension USState {
    /// The zone most of the state keeps, for a place whose own zone the dataset lacks.
    /// States split between zones take the one most of their people live in.
    public var mainTimeZone: TimeZone? {
        Self.mainTimeZones[code].flatMap(TimeZone.init(identifier:))
    }

    private static let mainTimeZones: [String: String] = [
        "AL": "America/Chicago", "AK": "America/Anchorage", "AZ": "America/Phoenix",
        "AR": "America/Chicago", "CA": "America/Los_Angeles", "CO": "America/Denver",
        "CT": "America/New_York", "DE": "America/New_York", "DC": "America/New_York",
        "FL": "America/New_York", "GA": "America/New_York", "HI": "Pacific/Honolulu",
        "ID": "America/Boise", "IL": "America/Chicago", "IN": "America/Indiana/Indianapolis",
        "IA": "America/Chicago", "KS": "America/Chicago", "KY": "America/New_York",
        "LA": "America/Chicago", "ME": "America/New_York", "MD": "America/New_York",
        "MA": "America/New_York", "MI": "America/Detroit", "MN": "America/Chicago",
        "MS": "America/Chicago", "MO": "America/Chicago", "MT": "America/Denver",
        "NE": "America/Chicago", "NV": "America/Los_Angeles", "NH": "America/New_York",
        "NJ": "America/New_York", "NM": "America/Denver", "NY": "America/New_York",
        "NC": "America/New_York", "ND": "America/Chicago", "OH": "America/New_York",
        "OK": "America/Chicago", "OR": "America/Los_Angeles", "PA": "America/New_York",
        "RI": "America/New_York", "SC": "America/New_York", "SD": "America/Chicago",
        "TN": "America/Chicago", "TX": "America/Chicago", "UT": "America/Denver",
        "VT": "America/New_York", "VA": "America/New_York", "WA": "America/Los_Angeles",
        "WV": "America/New_York", "WI": "America/Chicago", "WY": "America/Denver",
        "PR": "America/Puerto_Rico", "VI": "America/St_Thomas", "GU": "Pacific/Guam",
        "MP": "Pacific/Saipan", "AS": "Pacific/Pago_Pago",
    ]
}
