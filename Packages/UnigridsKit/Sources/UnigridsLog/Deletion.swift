import Foundation
import SwiftData
import UnigridsCore

/// A change to the log that can be taken back (SPECIFICATION.md §9, "Edit or delete
/// anything; undo for deletions").
///
/// Kept as values rather than left to the context's undo manager: SwiftData's undo depends
/// on run-loop grouping that a change made from a button cannot rely on, and these restore
/// records under their own identifiers — which is what an undo has to do to sync cleanly.
///
/// A deletion keeps the archive of what it removed, and undoing it merges that back. A
/// creation — a stamp, a photo import — keeps the identifiers it made, and undoing it
/// removes them.
public struct UndoableChange: Sendable {
    public enum Subject: Sendable, Equatable {
        case visit(UnigridsID, stamps: Int)
        case trip(String)
        case stamp(UnigridsID)
        case stop(UnigridsID)
        case reminder(String)
        case hike(UnigridsID)
        case stamped(UnigridsID)
        case hiked(UnigridsID)
        case imported(visits: Int, trips: Int, stamps: Int)
    }

    public let subject: Subject
    /// Records to merge back in.
    let putBack: LogArchive
    /// Records to remove.
    let takeOut: RecordIDs
    /// Visits to link to a trip again once it is back: a trip's deletion unlinks its
    /// visits rather than deleting them.
    let relink: [UUID: UUID]

    public init(
        subject: Subject,
        putBack: LogArchive = LogArchive(),
        takeOut: RecordIDs = RecordIDs(),
        relink: [UUID: UUID] = [:]
    ) {
        self.subject = subject
        self.putBack = putBack
        self.takeOut = takeOut
        self.relink = relink
    }

    /// Reminders an undo puts back, which the app has to schedule again.
    public var restoredReminders: [ReminderArchive] {
        putBack.trips.flatMap(\.reminders)
    }

    /// Reminders the change removed, which the app must stop notifying about.
    public var removedReminderIDs: [UUID] {
        putBack.trips.flatMap(\.reminders).map(\.id) + takeOut.reminders
    }

    /// "Visit to Zion and its stamp deleted", for the undo prompt.
    public func summary(
        placeName: (UnigridsID) -> String?,
        trailName: (UnigridsID) -> String? = { _ in nil }
    ) -> String {
        func place(_ id: UnigridsID) -> String {
            placeName(id) ?? "a place"
        }
        switch subject {
        case let .visit(id, stamps):
            switch stamps {
            case 0: return "Visit to \(place(id)) deleted"
            case 1: return "Visit to \(place(id)) and its stamp deleted"
            default: return "Visit to \(place(id)) and its \(stamps) stamps deleted"
            }
        case let .trip(name):
            return "\(name.isEmpty ? "Trip" : name) deleted"
        case let .stamp(id):
            return "Stamp for \(place(id)) deleted"
        case let .stop(id):
            return "\(place(id)) taken off the trip"
        case let .reminder(title):
            return "\(title.isEmpty ? "Reminder" : title) deleted"
        case let .hike(id):
            return "Hike on \(trailName(id) ?? "the trail") deleted"
        case let .stamped(id):
            return "Stamped \(place(id))"
        case let .hiked(id):
            return "Hike on \(trailName(id) ?? "the trail") logged"
        case let .imported(visits, trips, stamps):
            var parts = ["\(visits) visit\(visits == 1 ? "" : "s")"]
            if trips > 0 {
                parts.append("\(trips) trip\(trips == 1 ? "" : "s")")
            }
            if stamps > 0 {
                parts.append("\(stamps) stamp\(stamps == 1 ? "" : "s")")
            }
            return "Imported " + ListFormatter.localizedString(byJoining: parts)
        }
    }
}

/// Identifiers of records to remove when a change is undone.
public struct RecordIDs: Sendable, Equatable {
    public var visits: [UUID] = []
    public var trips: [UUID] = []
    public var stamps: [UUID] = []
    public var stops: [UUID] = []
    public var reminders: [UUID] = []
    public var hikes: [UUID] = []
    public var checkIns: [UUID] = []

    public init(
        visits: [UUID] = [],
        trips: [UUID] = [],
        stamps: [UUID] = [],
        stops: [UUID] = [],
        reminders: [UUID] = [],
        hikes: [UUID] = [],
        checkIns: [UUID] = []
    ) {
        self.visits = visits
        self.trips = trips
        self.stamps = stamps
        self.stops = stops
        self.reminders = reminders
        self.hikes = hikes
        self.checkIns = checkIns
    }
}

extension LogStore {
    /// Delete a visit and everything it holds: its check-ins, hikes, weather and its
    /// stamps. A stamp is the passport's record of a visit, and one left behind would have
    /// the passport and the log disagree about where the reader has been.
    @discardableResult
    public func delete(visit: Visit) throws -> UndoableChange {
        let stamps = visit.stamps ?? []
        let change = UndoableChange(
            subject: .visit(visit.place, stamps: stamps.count),
            putBack: LogArchive(
                visits: [VisitArchive(visit, name: { _ in nil })],
                stamps: stamps.map { StampArchive($0, name: { _ in nil }, calendar: nil) }
            )
        )
        for stamp in stamps {
            context.delete(stamp)
        }
        context.delete(visit)
        try save()
        return change
    }

    /// Delete a trip with its stops and reminders. Its visits stay in the log; an undo
    /// links them to the trip again.
    @discardableResult
    public func delete(trip: Trip) throws -> UndoableChange {
        let visits = trip.visits ?? []
        let change = UndoableChange(
            subject: .trip(trip.name),
            putBack: LogArchive(trips: [TripArchive(trip, name: { _ in nil })]),
            relink: Dictionary(uniqueKeysWithValues: visits.map { ($0.id, trip.id) })
        )
        context.delete(trip)
        try save()
        return change
    }

    /// Delete a stamp. A visit that only existed because of it — made by stamping, with
    /// nothing else logged on it — goes with it, so no empty visit is left counting
    /// towards anything.
    @discardableResult
    public func delete(stamp: Stamp) throws -> UndoableChange {
        var archive = LogArchive(stamps: [StampArchive(stamp, name: { _ in nil }, calendar: nil)])
        let visit = stamp.visit
        context.delete(stamp)
        if let visit, isEmpty(visit, ignoringStamp: stamp.id), visit.source == .stamp {
            archive.visits = [VisitArchive(visit, name: { _ in nil })]
            context.delete(visit)
        }
        try save()
        return UndoableChange(subject: .stamp(stamp.place), putBack: archive)
    }

    /// Take a stop off its trip.
    @discardableResult
    public func delete(stop: TripStop) throws -> UndoableChange {
        guard let trip = stop.trip else {
            context.delete(stop)
            try save()
            return UndoableChange(subject: .stop(stop.place))
        }
        var shell = TripArchive(trip, name: { _ in nil })
        shell.stops = [StopArchive(stop, name: { _ in nil })]
        shell.reminders = []
        context.delete(stop)
        try save()
        return UndoableChange(subject: .stop(stop.place), putBack: LogArchive(trips: [shell]))
    }

    /// Delete a reminder.
    @discardableResult
    public func delete(reminder: Reminder) throws -> UndoableChange {
        let subject = UndoableChange.Subject.reminder(reminder.title)
        guard let trip = reminder.trip else {
            context.delete(reminder)
            try save()
            return UndoableChange(subject: subject, takeOut: RecordIDs())
        }
        var shell = TripArchive(trip, name: { _ in nil })
        shell.stops = []
        shell.reminders = [ReminderArchive(reminder)]
        context.delete(reminder)
        try save()
        return UndoableChange(subject: subject, putBack: LogArchive(trips: [shell]))
    }

    /// Delete one hike, and the trail check-in that marking it made. A visit that began
    /// with the hike and holds nothing else goes too.
    @discardableResult
    public func delete(hike: Hike) throws -> UndoableChange {
        let subject = UndoableChange.Subject.hike(UnigridsID(hike.trailID))
        guard let visit = hike.visit else {
            context.delete(hike)
            try save()
            return UndoableChange(subject: subject)
        }
        let checkIns = (visit.checkIns ?? []).filter {
            $0.targetKindRaw == "trail" && $0.targetID == hike.trailID
                && abs($0.date.timeIntervalSince(hike.date)) < 1
        }
        var shell = VisitArchive(visit, name: { _ in nil })
        shell.hikes = [HikeArchive(hike)]
        shell.checkIns = checkIns.map(CheckInArchive.init)
        shell.weather = nil
        let removed = Set([hike.id] + checkIns.map(\.id))
        context.delete(hike)
        for checkIn in checkIns {
            context.delete(checkIn)
        }
        if visit.source == .hike, isEmpty(visit, ignoring: removed) {
            shell = VisitArchive(visit, name: { _ in nil })
            context.delete(visit)
        }
        try save()
        return UndoableChange(subject: subject, putBack: LogArchive(visits: [shell]))
    }

    /// Take back a change: remove what it made, put back what it removed.
    public func undo(_ change: UndoableChange) throws {
        try remove(change.takeOut)
        try merge(change.putBack)
        if !change.relink.isEmpty {
            let trips = try Dictionary(
                context.fetch(FetchDescriptor<Trip>()).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for visit in try context.fetch(FetchDescriptor<Visit>()) {
                if let tripID = change.relink[visit.id], let trip = trips[tripID] {
                    visit.trip = trip
                }
            }
        }
        try save()
    }

    private func remove(_ ids: RecordIDs) throws {
        func delete<Model: PersistentModel>(
            _: Model.Type, _ wanted: [UUID], id: (Model) -> UUID
        ) throws {
            guard !wanted.isEmpty else { return }
            let set = Set(wanted)
            let records = try context.fetch(FetchDescriptor<Model>())
            for record in records where set.contains(id(record)) {
                context.delete(record)
            }
        }
        try delete(Stamp.self, ids.stamps) { $0.id }
        try delete(Hike.self, ids.hikes) { $0.id }
        try delete(CheckIn.self, ids.checkIns) { $0.id }
        try delete(Visit.self, ids.visits) { $0.id }
        try delete(TripStop.self, ids.stops) { $0.id }
        try delete(Reminder.self, ids.reminders) { $0.id }
        try delete(Trip.self, ids.trips) { $0.id }
    }

    /// Whether a visit holds anything but the records about to go: no check-ins, hikes or
    /// stamps besides them, no rating and no notes.
    private func isEmpty(
        _ visit: Visit,
        ignoring removed: Set<UUID> = [],
        ignoringStamp stamp: UUID? = nil
    ) -> Bool {
        let skip = removed.union(stamp.map { [$0] } ?? [])
        let checkIns = (visit.checkIns ?? []).filter { !skip.contains($0.id) }
        let hikes = (visit.hikes ?? []).filter { !skip.contains($0.id) }
        let stamps = (visit.stamps ?? []).filter { !skip.contains($0.id) }
        return checkIns.isEmpty && hikes.isEmpty && stamps.isEmpty
            && visit.rating == nil && visit.notes.isEmpty
    }
}

// MARK: - Taking back what was made

extension LogStore {
    /// The change that takes a stamp back: the stamp, and its visit if stamping made it.
    public func undoing(stamp: Stamp, madeVisit: Bool) -> UndoableChange {
        UndoableChange(
            subject: .stamped(stamp.place),
            takeOut: RecordIDs(
                visits: madeVisit ? stamp.visit.map { [$0.id] } ?? [] : [],
                stamps: [stamp.id]
            )
        )
    }

    /// The change that takes a hike back: the hike, the trail check-in marking it made,
    /// and its visit if marking it made that too.
    public func undoing(hike: Hike, madeVisit: Bool) -> UndoableChange {
        let checkIns = (hike.visit?.checkIns ?? []).filter {
            $0.targetKindRaw == "trail" && $0.targetID == hike.trailID
                && abs($0.date.timeIntervalSince(hike.date)) < 1
        }
        return UndoableChange(
            subject: .hiked(UnigridsID(hike.trailID)),
            takeOut: RecordIDs(
                visits: madeVisit ? hike.visit.map { [$0.id] } ?? [] : [],
                hikes: [hike.id],
                checkIns: checkIns.map(\.id)
            )
        )
    }
}
