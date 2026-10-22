import Foundation
import SwiftData
import UnigridsCore

/// The reader's log as plain values: every record and every field, in a form that can be
/// written out, read back and put into a store under its own identifiers.
///
/// One shape serves three jobs, so none of them can quietly drop a field the others keep:
///
///  * **Export** (SPECIFICATION.md §9, "Ownership of data"): the JSON backup is this,
///    with place names added so it stays readable after the reference data moves on.
///  * **Import**: a backup merges back in by record identifier, so importing twice, or
///    into a log that already holds some of it, never duplicates anything.
///  * **Undo**: a deletion keeps the archive of exactly what it removed, and undoing it is
///    a merge.
public struct LogArchive: Codable, Sendable, Equatable {
    /// 2: every model and field. 1 was the first export, which held only visits, stamps
    /// and trips in brief, and still imports.
    public static let currentVersion = 2

    public var version: Int
    public var exportedAt: Date
    public var trips: [TripArchive]
    public var visits: [VisitArchive]
    public var stamps: [StampArchive]

    public init(
        version: Int = LogArchive.currentVersion,
        exportedAt: Date = Date(),
        trips: [TripArchive] = [],
        visits: [VisitArchive] = [],
        stamps: [StampArchive] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.trips = trips
        self.visits = visits
        self.stamps = stamps
    }

    public var isEmpty: Bool {
        trips.isEmpty && visits.isEmpty && stamps.isEmpty
    }
}

public struct TripArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var startDate: Date?
    public var endDate: Date?
    public var status: String
    public var notes: String
    public var createdAt: Date
    public var stops: [StopArchive]
    public var reminders: [ReminderArchive]
}

public struct StopArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var placeID: String
    public var placeName: String?
    public var plannedDate: Date?
    public var isTimed: Bool
    public var order: Int
    public var notes: String
    public var createdAt: Date
    public var targetKind: String
    public var targetID: String?
    public var customName: String?
    public var latitude: Double?
    public var longitude: Double?
}

public struct ReminderArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: String
    public var date: Date
    public var title: String
    public var url: String?
    public var timeZoneID: String?
}

public struct VisitArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var placeID: String
    public var placeName: String?
    public var date: Date
    public var endDate: Date?
    public var source: String
    public var rating: Int?
    public var notes: String
    public var createdAt: Date
    public var tripID: UUID?
    public var checkIns: [CheckInArchive]
    public var hikes: [HikeArchive]
    public var weather: WeatherArchive?
}

public struct CheckInArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var targetKind: String
    public var targetID: String
    public var date: Date
    public var photoAssetIdentifiers: [String]
    public var notes: String
}

public struct HikeArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var trailID: String
    public var date: Date
    public var completion: String
}

public struct WeatherArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var highCelsius: Double?
    public var lowCelsius: Double?
    public var precipitationMillimetres: Double?
    public var condition: String?
    public var source: String
}

public struct StampArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var placeID: String
    public var placeName: String?
    public var stampLocationID: String?
    public var date: Date
    public var seedBits: Int64
    public var isVerifiedOnSite: Bool
    public var realStampCollected: Bool
    public var createdAt: Date
    public var visitID: UUID?
    /// Derived on export, for a reader of the file; ignored on import.
    public var america250: Bool?
}

// MARK: - From the store

extension TripArchive {
    init(_ trip: Trip, name: (UnigridsID) -> String?) {
        id = trip.id
        self.name = trip.name
        startDate = trip.startDate
        endDate = trip.endDate
        status = trip.statusRaw
        notes = trip.notes
        createdAt = trip.createdAt
        stops = trip.orderedStops.map { StopArchive($0, name: name) }
        reminders = (trip.reminders ?? []).sorted { $0.date < $1.date }.map(ReminderArchive.init)
    }
}

extension StopArchive {
    init(_ stop: TripStop, name: (UnigridsID) -> String?) {
        id = stop.id
        placeID = stop.placeID
        placeName = name(stop.place)
        plannedDate = stop.plannedDate
        isTimed = stop.isTimed
        order = stop.order
        notes = stop.notes
        createdAt = stop.createdAt
        targetKind = stop.targetKindRaw
        targetID = stop.targetID
        customName = stop.customName
        latitude = stop.latitude
        longitude = stop.longitude
    }
}

extension ReminderArchive {
    init(_ reminder: Reminder) {
        id = reminder.id
        kind = reminder.kindRaw
        date = reminder.date
        title = reminder.title
        url = reminder.urlString
        timeZoneID = reminder.timeZoneID
    }
}

extension VisitArchive {
    init(_ visit: Visit, name: (UnigridsID) -> String?) {
        id = visit.id
        placeID = visit.placeID
        placeName = name(visit.place)
        date = visit.date
        endDate = visit.endDate
        source = visit.sourceRaw
        rating = visit.rating
        notes = visit.notes
        createdAt = visit.createdAt
        tripID = visit.trip?.id
        checkIns = (visit.checkIns ?? []).sorted { $0.date < $1.date }.map(CheckInArchive.init)
        hikes = (visit.hikes ?? []).sorted { $0.date < $1.date }.map(HikeArchive.init)
        weather = visit.weather.map(WeatherArchive.init)
    }
}

extension CheckInArchive {
    init(_ checkIn: CheckIn) {
        id = checkIn.id
        targetKind = checkIn.targetKindRaw
        targetID = checkIn.targetID
        date = checkIn.date
        photoAssetIdentifiers = checkIn.photoAssetIdentifiers
        notes = checkIn.notes
    }
}

extension HikeArchive {
    init(_ hike: Hike) {
        id = hike.id
        trailID = hike.trailID
        date = hike.date
        completion = hike.completionRaw
    }
}

extension WeatherArchive {
    init(_ weather: WeatherSnapshot) {
        id = weather.id
        date = weather.date
        highCelsius = weather.highCelsius
        lowCelsius = weather.lowCelsius
        precipitationMillimetres = weather.precipitationMillimetres
        condition = weather.condition
        source = weather.sourceRaw
    }
}

extension StampArchive {
    init(_ stamp: Stamp, name: (UnigridsID) -> String?, calendar: Calendar?) {
        id = stamp.id
        placeID = stamp.placeID
        placeName = name(stamp.place)
        stampLocationID = stamp.stampLocationID
        date = stamp.date
        seedBits = stamp.seedBits
        isVerifiedOnSite = stamp.isVerifiedOnSite
        realStampCollected = stamp.realStampCollected
        createdAt = stamp.createdAt
        visitID = stamp.visit?.id
        america250 = calendar.map { stamp.hasAmerica250Seal(calendar: $0) }
    }
}

// MARK: - Reading and writing

extension LogArchive {
    /// The whole log. `name` resolves a place id to its current name, for the export;
    /// `calendar` decides the America 250 flag written beside each stamp.
    @MainActor
    public static func of(
        _ context: ModelContext,
        name: (UnigridsID) -> String? = { _ in nil },
        calendar: (UnigridsID) -> Calendar? = { _ in nil }
    ) throws -> LogArchive {
        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt)]))
        let visits = try context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.date)]))
        let stamps = try context.fetch(FetchDescriptor<Stamp>(sortBy: [SortDescriptor(\.date)]))
        return LogArchive(
            trips: trips.map { TripArchive($0, name: name) },
            visits: visits.map { VisitArchive($0, name: name) },
            stamps: stamps.map { StampArchive($0, name: name, calendar: calendar($0.place)) }
        )
    }

    /// ISO 8601 with milliseconds: whole seconds would reorder records made in the same
    /// second once they came back.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.string(from: date))
        }
        return try encoder.encode(self)
    }

    /// A backup, of this version or the first, with or without milliseconds.
    public static func decode(_ data: Data) throws -> LogArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let date = try (try? Date(text, strategy: dateFormat)) ?? Date(text, strategy: .iso8601)
            // To the millisecond the file holds, so writing it out again gives the same text.
            return Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
        }
        if let archive = try? decoder.decode(LogArchive.self, from: data) {
            return archive
        }
        return try decoder.decode(LegacyExport.self, from: data).archive
    }

    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// `2026-07-04T18:00:00.250Z`. The milliseconds are counted here, rounded, rather than
    /// left to the formatter, which truncates — a date read back as .29999… would write
    /// out as .299.
    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let whole = Date(timeIntervalSince1970: seconds).formatted(.iso8601)
        return whole.dropLast() + String(format: ".%03dZ", fraction)
    }
}

/// The first export's shape, read so a backup made before version 2 still restores what
/// it holds. It kept no check-in kinds, hikes, weather, reminders or stamp locations, so
/// none come back.
private struct LegacyExport: Decodable {
    struct Visit: Decodable {
        let id: UUID
        let placeID: String
        let date: Date
        let source: String
        let rating: Int?
        let notes: String
        let trip: UUID?
    }

    struct Stamp: Decodable {
        let id: UUID
        let placeID: String
        let date: Date
        let verifiedOnSite: Bool
        let realStampCollected: Bool
    }

    struct Trip: Decodable {
        let id: UUID
        let name: String
        let status: String
        let startDate: Date?
        let endDate: Date?
        let notes: String
        let stops: [String]
    }

    let exportedAt: Date
    let visits: [Visit]
    let stamps: [Stamp]
    let trips: [Trip]

    /// The visit a stamp joined. The first export kept no link, but stamping always made
    /// or joined a visit at the place within the day, so the nearest such visit is it.
    func visit(for stamp: Stamp) -> Visit? {
        visits
            .filter {
                $0.placeID == stamp.placeID && abs($0.date.timeIntervalSince(stamp.date)) < 86400
            }
            .min {
                abs($0.date.timeIntervalSince(stamp.date)) <
                    abs($1.date.timeIntervalSince(stamp.date))
            }
    }

    var archive: LogArchive {
        LogArchive(
            version: 1,
            exportedAt: exportedAt,
            trips: trips.map { trip in
                TripArchive(
                    id: trip.id, name: trip.name, startDate: trip.startDate,
                    endDate: trip.endDate, status: trip.status, notes: trip.notes,
                    createdAt: exportedAt,
                    stops: trip.stops.enumerated().map { index, place in
                        // A stop's identity is new; it was not in the file to keep.
                        StopArchive(
                            id: UUID(), placeID: place, placeName: nil, plannedDate: nil,
                            isTimed: false, order: index, notes: "", createdAt: exportedAt,
                            targetKind: "place", targetID: nil, customName: nil,
                            latitude: nil, longitude: nil
                        )
                    },
                    reminders: []
                )
            },
            visits: visits.map { visit in
                VisitArchive(
                    id: visit.id, placeID: visit.placeID, placeName: nil, date: visit.date,
                    endDate: nil, source: visit.source, rating: visit.rating,
                    notes: visit.notes, createdAt: visit.date, tripID: visit.trip,
                    checkIns: [], hikes: [], weather: nil
                )
            },
            stamps: stamps.map { stamp in
                StampArchive(
                    id: stamp.id, placeID: stamp.placeID, placeName: nil, stampLocationID: nil,
                    date: stamp.date, seedBits: Int64(bitPattern: StampImpression.newSeed()),
                    isVerifiedOnSite: stamp.verifiedOnSite,
                    realStampCollected: stamp.realStampCollected, createdAt: stamp.date,
                    visitID: visit(for: stamp)?.id, america250: nil
                )
            }
        )
    }
}
