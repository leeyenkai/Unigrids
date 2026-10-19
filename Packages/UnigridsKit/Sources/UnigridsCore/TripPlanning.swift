import Foundation

/// Straight-line distances along a trip's stops, in order (SPECIFICATION.md §10).
///
/// Drive times come from MapKit directions when the planner asks for them online; this is
/// the figure that is always available, offline included, and it is labelled as straight
/// line wherever it is shown so nobody plans a day's driving on it.
public enum TripRoute {
    /// The distance of each leg, first stop to second and onward. One fewer than stops.
    public static func legDistances(_ stops: [Coordinate]) -> [Double] {
        zip(stops, stops.dropFirst()).map { $0.distance(to: $1) }
    }

    public static func totalDistance(_ stops: [Coordinate]) -> Double {
        legDistances(stops).reduce(0, +)
    }
}

/// A trip as an iCalendar file, for Apple Calendar or any other (SPECIFICATION.md §10,
/// "Export to Apple Calendar or as an .ics file").
///
/// Pure text, built here rather than through EventKit so the export needs no calendar
/// permission and the format can be tested.
public enum TripCalendar {
    public struct Event: Hashable, Sendable {
        public let title: String
        public let day: Date
        public let notes: String?

        public init(title: String, day: Date, notes: String? = nil) {
            self.title = title
            self.day = day
            self.notes = notes
        }
    }

    /// An iCalendar document with one all-day event per stop that has a date.
    ///
    /// `identifier` seeds each event's UID, so exporting the same trip twice updates the
    /// events in a calendar app rather than duplicating them.
    public static func document(
        name: String,
        events: [Event],
        identifier: String,
        stamp: Date,
        calendar: Calendar = .current
    ) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Unigrids//Trip export//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:\(escape(name))",
        ]
        for (index, event) in events.enumerated() {
            let start = calendar.startOfDay(for: event.day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            lines += [
                "BEGIN:VEVENT",
                "UID:\(identifier)-\(index)@unigrids",
                "DTSTAMP:\(timestamp(stamp))",
                "DTSTART;VALUE=DATE:\(day(start, calendar: calendar))",
                "DTEND;VALUE=DATE:\(day(end, calendar: calendar))",
                "SUMMARY:\(escape(event.title))",
            ]
            if let notes = event.notes, !notes.isEmpty {
                lines.append("DESCRIPTION:\(escape(notes))")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        // The format requires CRLF line endings.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Text escaped as RFC 5545 requires: backslash, semicolon, comma and newline.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1
        )
    }

    private static func timestamp(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }
}
