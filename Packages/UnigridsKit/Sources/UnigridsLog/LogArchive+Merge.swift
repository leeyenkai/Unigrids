import Foundation
import SwiftData
import UnigridsCore

/// What a merge put in, and what it found already there.
public struct MergeSummary: Equatable, Sendable {
    public var tripsAdded = 0
    public var visitsAdded = 0
    public var stampsAdded = 0
    public var alreadyPresent = 0

    public var added: Int {
        tripsAdded + visitsAdded + stampsAdded
    }
}

extension LogStore {
    /// The whole log as an archive.
    public func archive(
        name: (UnigridsID) -> String? = { _ in nil },
        calendar: (UnigridsID) -> Calendar? = { _ in nil }
    ) throws -> LogArchive {
        try LogArchive.of(context, name: name, calendar: calendar)
    }

    /// Put every record of `archive` that the log does not already hold into it, under its
    /// own identifiers, and link them up: stops and reminders to their trip, visits to
    /// theirs, stamps to their visit. A record whose identifier is already in the log is
    /// left as the log has it — the log is the newer of the two.
    @discardableResult
    public func merge(_ archive: LogArchive) throws -> MergeSummary {
        var summary = MergeSummary()
        let trips = try mergeTrips(archive.trips, into: &summary)
        let visits = try mergeVisits(archive.visits, trips: trips, into: &summary)
        try mergeStamps(archive.stamps, visits: visits, into: &summary)
        try save()
        return summary
    }

    private func ids<Model: PersistentModel>(
        _: Model.Type,
        _ id: (Model) -> UUID
    ) throws -> Set<UUID> {
        try Set(context.fetch(FetchDescriptor<Model>()).map(id))
    }

    private func mergeTrips(
        _ items: [TripArchive], into summary: inout MergeSummary
    ) throws -> [UUID: Trip] {
        var trips = try Dictionary(
            context.fetch(FetchDescriptor<Trip>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let stops = try ids(TripStop.self) { $0.id }
        let reminders = try ids(Reminder.self) { $0.id }
        for item in items {
            let trip: Trip
            if let existing = trips[item.id] {
                trip = existing
                summary.alreadyPresent += 1
            } else {
                trip = Trip(
                    name: item.name, startDate: item.startDate, endDate: item.endDate,
                    status: TripStatus(rawValue: item.status) ?? .planned, notes: item.notes
                )
                trip.restoreIdentity(item.id, createdAt: item.createdAt)
                context.insert(trip)
                trips[item.id] = trip
                summary.tripsAdded += 1
            }
            for stop in item.stops where !stops.contains(stop.id) {
                insert(stop, into: trip)
            }
            for reminder in item.reminders where !reminders.contains(reminder.id) {
                insert(reminder, into: trip)
            }
        }
        return trips
    }

    private func insert(_ stop: StopArchive, into trip: Trip) {
        let record = TripStop(
            placeID: UnigridsID(stop.placeID), order: stop.order,
            plannedDate: stop.plannedDate, notes: stop.notes
        )
        record.restoreIdentity(stop.id, createdAt: stop.createdAt)
        record.isTimed = stop.isTimed
        record.targetKindRaw = stop.targetKind
        record.targetID = stop.targetID
        record.customName = stop.customName
        record.latitude = stop.latitude
        record.longitude = stop.longitude
        record.trip = trip
        context.insert(record)
    }

    private func insert(_ reminder: ReminderArchive, into trip: Trip) {
        let record = Reminder(
            kind: Reminder.Kind(rawValue: reminder.kind) ?? .permit,
            date: reminder.date,
            title: reminder.title,
            url: reminder.url.flatMap(URL.init(string:))
        )
        record.restoreIdentity(reminder.id)
        record.timeZoneID = reminder.timeZoneID
        record.trip = trip
        context.insert(record)
    }

    private func mergeVisits(
        _ items: [VisitArchive], trips: [UUID: Trip], into summary: inout MergeSummary
    ) throws -> [UUID: Visit] {
        var visits = try Dictionary(
            context.fetch(FetchDescriptor<Visit>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let checkIns = try ids(CheckIn.self) { $0.id }
        let hikes = try ids(Hike.self) { $0.id }
        for item in items {
            let visit: Visit
            if let existing = visits[item.id] {
                visit = existing
                summary.alreadyPresent += 1
            } else {
                visit = Visit(
                    placeID: UnigridsID(item.placeID), date: item.date, endDate: item.endDate,
                    rating: item.rating, notes: item.notes
                )
                visit.restoreIdentity(item.id, createdAt: item.createdAt)
                visit.sourceRaw = item.source
                visit.trip = item.tripID.flatMap { trips[$0] }
                context.insert(visit)
                visits[item.id] = visit
                summary.visitsAdded += 1
            }
            for checkIn in item.checkIns where !checkIns.contains(checkIn.id) {
                let record = CheckIn(target: .place(""), date: checkIn.date, notes: checkIn.notes)
                record.restoreIdentity(checkIn.id)
                record.targetKindRaw = checkIn.targetKind
                record.targetID = checkIn.targetID
                record.photoAssetIdentifiers = checkIn.photoAssetIdentifiers
                record.visit = visit
                context.insert(record)
            }
            for hike in item.hikes where !hikes.contains(hike.id) {
                let record = Hike(trailID: UnigridsID(hike.trailID), date: hike.date)
                record.restoreIdentity(hike.id)
                record.completionRaw = hike.completion
                record.visit = visit
                context.insert(record)
            }
            if let weather = item.weather, visit.weather == nil {
                insert(weather, into: visit)
            }
        }
        return visits
    }

    private func insert(_ weather: WeatherArchive, into visit: Visit) {
        let record = WeatherSnapshot(
            date: weather.date, highCelsius: weather.highCelsius,
            lowCelsius: weather.lowCelsius,
            precipitationMillimetres: weather.precipitationMillimetres,
            condition: weather.condition,
            source: WeatherSnapshot.Source(rawValue: weather.source) ?? .openMeteoArchive
        )
        record.restoreIdentity(weather.id)
        record.visit = visit
        context.insert(record)
    }

    private func mergeStamps(
        _ items: [StampArchive], visits: [UUID: Visit], into summary: inout MergeSummary
    ) throws {
        let stamps = try ids(Stamp.self) { $0.id }
        for item in items {
            guard !stamps.contains(item.id) else {
                summary.alreadyPresent += 1
                continue
            }
            let stamp = Stamp(
                placeID: UnigridsID(item.placeID),
                stampLocationID: item.stampLocationID.map { UnigridsID($0) },
                date: item.date,
                seed: UInt64(bitPattern: item.seedBits),
                isVerifiedOnSite: item.isVerifiedOnSite,
                realStampCollected: item.realStampCollected
            )
            stamp.restoreIdentity(item.id, createdAt: item.createdAt)
            stamp.visit = item.visitID.flatMap { visits[$0] }
            context.insert(stamp)
            summary.stampsAdded += 1
        }
    }
}
