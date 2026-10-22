import Foundation
import SwiftData
import UnigridsCore

/// A deleted record, kept as values so it can be put back (SPECIFICATION.md §9, "Edit or
/// delete anything; undo for deletions").
///
/// A snapshot rather than the context's undo manager: SwiftData's undo depends on run-loop
/// grouping that a deletion made from a button cannot rely on, and a snapshot restores the
/// record under its own identifiers, with what the deletion cascaded to and the links it
/// cut, which is what an undo has to do to sync cleanly.
public enum DeletedRecord: Sendable {
    case visit(VisitRecord)
    case trip(TripRecord)
    case stamp(StampRecord)

    /// "Visit to Zion deleted", for the undo prompt, given a way to name places.
    public func summary(placeName: (UnigridsID) -> String?) -> String {
        switch self {
        case let .visit(record):
            "Visit to \(placeName(UnigridsID(record.placeID)) ?? "a place") deleted"
        case let .trip(record):
            "\(record.name.isEmpty ? "Trip" : record.name) deleted"
        case let .stamp(record):
            "Stamp for \(placeName(UnigridsID(record.placeID)) ?? "a place") deleted"
        }
    }
}

public struct VisitRecord: Sendable {
    struct CheckInRecord: Sendable {
        let id: UUID
        let targetKindRaw: String
        let targetID: String
        let date: Date
        let photoAssetIdentifiers: [String]
        let notes: String
    }

    struct HikeRecord: Sendable {
        let id: UUID
        let trailID: String
        let date: Date
        let completionRaw: String
    }

    struct WeatherRecord: Sendable {
        let date: Date
        let high: Double?
        let low: Double?
        let precipitation: Double?
        let condition: String?
        let sourceRaw: String
    }

    let id: UUID
    let placeID: String
    let date: Date
    let endDate: Date?
    let sourceRaw: String
    let rating: Int?
    let notes: String
    let createdAt: Date
    let tripID: UUID?
    let checkIns: [CheckInRecord]
    let hikes: [HikeRecord]
    let weather: WeatherRecord?
    let stampIDs: [UUID]
}

public struct TripRecord: Sendable {
    struct StopRecord: Sendable {
        let id: UUID
        let placeID: String
        let plannedDate: Date?
        let order: Int
        let notes: String
        let createdAt: Date
    }

    struct ReminderRecord: Sendable {
        let id: UUID
        let kindRaw: String
        let date: Date
        let title: String
        let urlString: String?
    }

    let id: UUID
    let name: String
    let startDate: Date?
    let endDate: Date?
    let statusRaw: String
    let notes: String
    let createdAt: Date
    let stops: [StopRecord]
    let reminders: [ReminderRecord]
    let visitIDs: [UUID]
}

public struct StampRecord: Sendable {
    let id: UUID
    let placeID: String
    let stampLocationID: String?
    let date: Date
    let seedBits: Int64
    let isVerifiedOnSite: Bool
    let realStampCollected: Bool
    let createdAt: Date
    let visitID: UUID?
}

extension LogStore {
    /// Delete a visit, returning what it takes to put it back.
    @discardableResult
    public func delete(visit: Visit) throws -> DeletedRecord {
        let record = VisitRecord(
            id: visit.id,
            placeID: visit.placeID,
            date: visit.date,
            endDate: visit.endDate,
            sourceRaw: visit.sourceRaw,
            rating: visit.rating,
            notes: visit.notes,
            createdAt: visit.createdAt,
            tripID: visit.trip?.id,
            checkIns: (visit.checkIns ?? []).map {
                .init(
                    id: $0.id, targetKindRaw: $0.targetKindRaw, targetID: $0.targetID,
                    date: $0.date, photoAssetIdentifiers: $0.photoAssetIdentifiers, notes: $0.notes
                )
            },
            hikes: (visit.hikes ?? []).map {
                .init(
                    id: $0.id,
                    trailID: $0.trailID,
                    date: $0.date,
                    completionRaw: $0.completionRaw
                )
            },
            weather: visit.weather.map {
                .init(
                    date: $0.date, high: $0.highCelsius, low: $0.lowCelsius,
                    precipitation: $0.precipitationMillimetres, condition: $0.condition,
                    sourceRaw: $0.sourceRaw
                )
            },
            stampIDs: (visit.stamps ?? []).map(\.id)
        )
        try delete(visit)
        return .visit(record)
    }

    /// Delete a trip, returning what it takes to put it back. Its visits stay in the log
    /// either way; an undo links them to the trip again.
    @discardableResult
    public func delete(trip: Trip) throws -> DeletedRecord {
        let record = TripRecord(
            id: trip.id,
            name: trip.name,
            startDate: trip.startDate,
            endDate: trip.endDate,
            statusRaw: trip.statusRaw,
            notes: trip.notes,
            createdAt: trip.createdAt,
            stops: (trip.stops ?? []).map {
                .init(
                    id: $0.id, placeID: $0.placeID, plannedDate: $0.plannedDate,
                    order: $0.order, notes: $0.notes, createdAt: $0.createdAt
                )
            },
            reminders: (trip.reminders ?? []).map {
                .init(
                    id: $0.id,
                    kindRaw: $0.kindRaw,
                    date: $0.date,
                    title: $0.title,
                    urlString: $0.urlString
                )
            },
            visitIDs: (trip.visits ?? []).map(\.id)
        )
        try delete(trip)
        return .trip(record)
    }

    /// Delete a stamp, returning what it takes to put it back.
    @discardableResult
    public func delete(stamp: Stamp) throws -> DeletedRecord {
        let record = StampRecord(
            id: stamp.id,
            placeID: stamp.placeID,
            stampLocationID: stamp.stampLocationID,
            date: stamp.date,
            seedBits: stamp.seedBits,
            isVerifiedOnSite: stamp.isVerifiedOnSite,
            realStampCollected: stamp.realStampCollected,
            createdAt: stamp.createdAt,
            visitID: stamp.visit?.id
        )
        try delete(stamp)
        return .stamp(record)
    }

    /// Put a deleted record back, under its own identifiers.
    public func restore(_ record: DeletedRecord) throws {
        switch record {
        case let .visit(record): try restore(record)
        case let .trip(record): try restore(record)
        case let .stamp(record): try restore(record)
        }
        try context.save()
    }

    private func restore(_ record: VisitRecord) throws {
        let visit = Visit(
            placeID: UnigridsID(record.placeID),
            date: record.date,
            endDate: record.endDate,
            rating: record.rating,
            notes: record.notes
        )
        visit.restoreIdentity(record.id, createdAt: record.createdAt)
        visit.sourceRaw = record.sourceRaw
        context.insert(visit)
        if let tripID = record.tripID {
            visit.trip = try fetch(Trip.self).first { $0.id == tripID }
        }
        for item in record.checkIns {
            let checkIn = CheckIn(target: .place(""), date: item.date, notes: item.notes)
            checkIn.restoreIdentity(item.id)
            checkIn.targetKindRaw = item.targetKindRaw
            checkIn.targetID = item.targetID
            checkIn.photoAssetIdentifiers = item.photoAssetIdentifiers
            checkIn.visit = visit
            context.insert(checkIn)
        }
        for item in record.hikes {
            let hike = Hike(trailID: UnigridsID(item.trailID), date: item.date)
            hike.restoreIdentity(item.id)
            hike.completionRaw = item.completionRaw
            hike.visit = visit
            context.insert(hike)
        }
        if let item = record.weather {
            let snapshot = WeatherSnapshot(
                date: item.date, highCelsius: item.high, lowCelsius: item.low,
                precipitationMillimetres: item.precipitation, condition: item.condition,
                source: WeatherSnapshot.Source(rawValue: item.sourceRaw) ?? .openMeteoArchive
            )
            snapshot.visit = visit
            context.insert(snapshot)
        }
        let stampIDs = Set(record.stampIDs)
        for stamp in try fetch(Stamp.self) where stampIDs.contains(stamp.id) {
            stamp.visit = visit
        }
    }

    private func restore(_ record: TripRecord) throws {
        let trip = Trip(
            name: record.name,
            startDate: record.startDate,
            endDate: record.endDate,
            notes: record.notes
        )
        trip.restoreIdentity(record.id, createdAt: record.createdAt)
        trip.statusRaw = record.statusRaw
        context.insert(trip)
        for item in record.stops {
            let stop = TripStop(
                placeID: UnigridsID(item.placeID), order: item.order,
                plannedDate: item.plannedDate, notes: item.notes
            )
            stop.restoreIdentity(item.id, createdAt: item.createdAt)
            stop.trip = trip
            context.insert(stop)
        }
        for item in record.reminders {
            let reminder = Reminder(
                kind: Reminder.Kind(rawValue: item.kindRaw) ?? .permit,
                date: item.date,
                title: item.title,
                url: item.urlString.flatMap(URL.init(string:))
            )
            reminder.restoreIdentity(item.id)
            reminder.trip = trip
            context.insert(reminder)
        }
        let visitIDs = Set(record.visitIDs)
        for visit in try fetch(Visit.self) where visitIDs.contains(visit.id) {
            visit.trip = trip
        }
    }

    private func restore(_ record: StampRecord) throws {
        let stamp = Stamp(
            placeID: UnigridsID(record.placeID),
            stampLocationID: record.stampLocationID.map { UnigridsID($0) },
            date: record.date,
            seed: UInt64(bitPattern: record.seedBits),
            isVerifiedOnSite: record.isVerifiedOnSite,
            realStampCollected: record.realStampCollected
        )
        stamp.restoreIdentity(record.id, createdAt: record.createdAt)
        if let visitID = record.visitID {
            stamp.visit = try fetch(Visit.self).first { $0.id == visitID }
        }
        context.insert(stamp)
    }

    private func fetch<Model: PersistentModel>(_: Model.Type) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }
}
