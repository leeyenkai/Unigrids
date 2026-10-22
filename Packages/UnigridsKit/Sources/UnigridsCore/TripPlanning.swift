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
        /// The stop's own identity: an event keeps its UID however the stops are
        /// reordered, so importing the trip again updates it rather than another.
        public let uid: String
        public let title: String
        public let day: Date
        /// Set when the stop has a time of day, not just a day.
        public let time: Date?
        public let notes: String?

        public init(
            uid: String,
            title: String,
            day: Date,
            time: Date? = nil,
            notes: String? = nil
        ) {
            self.uid = uid
            self.title = title
            self.day = day
            self.time = time
            self.notes = notes
        }
    }

    /// An iCalendar document with one event per stop that has a date: all day, or an hour
    /// from the time a timed stop names.
    ///
    /// `identifier` seeds each event's UID with the stop's own, so exporting the same trip
    /// twice updates the events in a calendar app rather than duplicating them.
    public static func document(
        name: String,
        events: [Event],
        identifier: String,
        stamp: Date,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Unigrids//Trip export//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:\(escape(name))",
        ]
        for event in events {
            lines += [
                "BEGIN:VEVENT",
                "UID:\(identifier)-\(event.uid)@unigrids",
                "DTSTAMP:\(timestamp(stamp))",
            ]
            if let time = event.time {
                lines += [
                    "DTSTART:\(timestamp(time))",
                    "DTEND:\(timestamp(time.addingTimeInterval(3600)))",
                ]
            } else {
                let start = calendar.startOfDay(for: event.day)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                lines += [
                    "DTSTART;VALUE=DATE:\(day(start, calendar: calendar))",
                    "DTEND;VALUE=DATE:\(day(end, calendar: calendar))",
                ]
            }
            lines.append("SUMMARY:\(escape(event.title))")
            if let notes = event.notes, !notes.isEmpty {
                lines.append("DESCRIPTION:\(escape(notes))")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        // The format requires CRLF line endings, and lines no longer than 75 octets.
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Text escaped as RFC 5545 requires: backslash, semicolon, comma and line breaks.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// A line folded at 75 octets, each continuation starting with a space (RFC 5545
    /// §3.1), never splitting a character.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var parts: [String] = []
        var current = ""
        var limit = 75
        for character in line {
            if current.utf8.count + character.utf8.count > limit {
                parts.append(current)
                current = ""
                limit = 74 // the leading space takes one
            }
            current.append(character)
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
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

/// A trip as GPX: one waypoint per place, in order, for any mapping app
/// (SPECIFICATION.md §9, "trips as GPX of visited points").
public enum TripGPX {
    public struct Waypoint: Hashable, Sendable {
        public let name: String
        public let coordinate: Coordinate
        public let date: Date?
        public let note: String?

        public init(name: String, coordinate: Coordinate, date: Date? = nil, note: String? = nil) {
            self.name = name
            self.coordinate = coordinate
            self.date = date
            self.note = note
        }
    }

    public static func document(name: String, waypoints: [Waypoint]) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Unigrids" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <metadata><name>\(escape(name))</name></metadata>",
        ]
        for point in waypoints {
            let lat = String(format: "%.5f", point.coordinate.latitude)
            let lon = String(format: "%.5f", point.coordinate.longitude)
            lines.append("  <wpt lat=\"\(lat)\" lon=\"\(lon)\">")
            if let date = point.date {
                lines.append("    <time>\(date.ISO8601Format())</time>")
            }
            lines.append("    <name>\(escape(point.name))</name>")
            if let note = point.note, !note.isEmpty {
                lines.append("    <desc>\(escape(note))</desc>")
            }
            lines.append("  </wpt>")
        }
        if waypoints.count > 1 {
            lines.append("  <rte><name>\(escape(name))</name>")
            for point in waypoints {
                let lat = String(format: "%.5f", point.coordinate.latitude)
                let lon = String(format: "%.5f", point.coordinate.longitude)
                let name = escape(point.name)
                let point = #"lat="\#(lat)" lon="\#(lon)""#
                lines.append("    <rtept \(point)><name>\(name)</name></rtept>")
            }
            lines.append("  </rte>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
