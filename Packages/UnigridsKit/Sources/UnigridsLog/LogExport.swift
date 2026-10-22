import Foundation
import SwiftData
import UnigridsCore

/// The reader's whole log in open formats (SPECIFICATION.md §9, "Ownership of data"): JSON
/// for everything — a `LogArchive`, which imports back — and CSV for the visits a
/// spreadsheet wants. Places are written by their stable id and, where it still resolves,
/// their name, so an export stays readable after the reference data moves on.
@MainActor
public enum LogExport {
    /// The whole log as a backup file's contents.
    public static func json(
        context: ModelContext,
        name: (UnigridsID) -> String?,
        calendar: (UnigridsID) -> Calendar
    ) throws -> Data {
        try LogArchive.of(context, name: name, calendar: calendar).json()
    }

    /// One row per visit, its date the day it was where it was. RFC 4180: fields with a
    /// comma, quote or line break are quoted, and quotes inside them doubled.
    public static func visitsCSV(
        _ archive: LogArchive,
        calendar: (UnigridsID) -> Calendar
    ) -> String {
        var lines = ["date,place,place_id,source,rating,notes"]
        for visit in archive.visits {
            lines.append([
                UnigridsCalendar.dayKey(visit.date, calendar: calendar(UnigridsID(visit.placeID))),
                visit.placeName ?? "",
                visit.placeID,
                visit.source,
                visit.rating.map(String.init) ?? "",
                visit.notes,
            ].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ value: String) -> String {
        var value = value
        // A spreadsheet runs a field that starts like a formula. A note is never one.
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        // `Character` comparisons treat "\r\n" as one character that is neither "\r" nor
        // "\n"; `isNewline` catches all three.
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
