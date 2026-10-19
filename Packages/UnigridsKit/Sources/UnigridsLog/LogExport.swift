import Foundation
import SwiftData
import UnigridsCore

/// The reader's whole log in open formats (SPECIFICATION.md §9, "Ownership of data"): JSON
/// for everything, CSV for the visits a spreadsheet wants. Places are written by their
/// stable id and, where it still resolves, their name — so an export stays readable after
/// the reference data moves on.
@MainActor
public enum LogExport {
    public struct Document: Codable, Sendable {
        public let exportedAt: Date
        public let visits: [VisitRecord]
        public let stamps: [StampRecord]
        public let trips: [TripRecord]
    }

    public struct VisitRecord: Codable, Sendable {
        public let id: UUID
        public let placeID: String
        public let placeName: String?
        public let date: Date
        public let source: String
        public let rating: Int?
        public let notes: String
        public let trip: UUID?
        public let checkIns: [String]
    }

    public struct StampRecord: Codable, Sendable {
        public let id: UUID
        public let placeID: String
        public let placeName: String?
        public let date: Date
        public let verifiedOnSite: Bool
        public let realStampCollected: Bool
        public let america250: Bool
    }

    public struct TripRecord: Codable, Sendable {
        public let id: UUID
        public let name: String
        public let status: String
        public let startDate: Date?
        public let endDate: Date?
        public let notes: String
        public let stops: [String]
    }

    /// Everything, as one document. `name` resolves a place id to its current name.
    public static func document(
        context: ModelContext,
        name: (UnigridsID) -> String?
    ) throws -> Document {
        let visits = try context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.date)]))
        let stamps = try context.fetch(FetchDescriptor<Stamp>(sortBy: [SortDescriptor(\.date)]))
        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt)]))
        return Document(
            exportedAt: Date(),
            visits: visits.map { visit in
                VisitRecord(
                    id: visit.id,
                    placeID: visit.placeID,
                    placeName: name(visit.place),
                    date: visit.date,
                    source: visit.source.rawValue,
                    rating: visit.rating,
                    notes: visit.notes,
                    trip: visit.trip?.id,
                    checkIns: (visit.checkIns ?? []).map(\.targetID)
                )
            },
            stamps: stamps.map { stamp in
                StampRecord(
                    id: stamp.id,
                    placeID: stamp.placeID,
                    placeName: name(stamp.place),
                    date: stamp.date,
                    verifiedOnSite: stamp.isVerifiedOnSite,
                    realStampCollected: stamp.realStampCollected,
                    america250: stamp.hasAmerica250Seal()
                )
            },
            trips: trips.map { trip in
                TripRecord(
                    id: trip.id,
                    name: trip.name,
                    status: trip.status.rawValue,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    notes: trip.notes,
                    stops: trip.orderedStops.map(\.placeID)
                )
            }
        )
    }

    public static func json(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// One row per visit. RFC 4180: fields with a comma, quote or newline are quoted, and
    /// quotes inside them doubled.
    public static func visitsCSV(_ document: Document) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var lines = ["date,place,place_id,source,rating,notes"]
        for visit in document.visits {
            lines.append([
                formatter.string(from: visit.date),
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
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
