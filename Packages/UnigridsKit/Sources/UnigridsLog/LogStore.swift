import Foundation
import SwiftData
import UnigridsCore

/// Everything that writes to the user's log goes through here.
///
/// Views read with `@Query` and write with this (`docs/adr/0004`), which keeps two rules
/// in one place rather than scattered across view bodies:
///
///  * **Nothing is logged without the user confirming it** (SPECIFICATION.md §9). Every
///    method here is the result of a confirmation the UI already collected.
///  * **Stamping creates or joins a visit**, so the passport and the trip log always
///    agree. That join is the subtle part, and it lives in `stamp(...)`.
@MainActor
public final class LogStore {
    let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = UnigridsCalendar.gregorian()) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Reading

    public func visits() throws -> [Visit] {
        try context.fetch(
            FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
    }

    public func visits(to placeID: UnigridsID) throws -> [Visit] {
        let raw = placeID.rawValue
        return try context.fetch(
            FetchDescriptor<Visit>(
                predicate: #Predicate { $0.placeID == raw },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    public func stamps() throws -> [Stamp] {
        try context.fetch(
            FetchDescriptor<Stamp>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
    }

    public func stamps(for placeID: UnigridsID) throws -> [Stamp] {
        let raw = placeID.rawValue
        return try context.fetch(
            FetchDescriptor<Stamp>(
                predicate: #Predicate { $0.placeID == raw },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    public func trips() throws -> [Trip] {
        try context.fetch(
            FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
    }

    /// The ids of every place with at least one visit, for the map's visited styling.
    public func visitedPlaceIDs() throws -> Set<UnigridsID> {
        try Set(visits().map(\.place))
    }

    public func isVisited(_ placeID: UnigridsID) throws -> Bool {
        try !visits(to: placeID).isEmpty
    }

    /// Visits reduced to what the stats need.
    public func visitSummaries() throws -> [VisitSummary] {
        try visits().map(\.summary)
    }

    public func hikeSummaries() throws -> [HikeSummary] {
        try context.fetch(FetchDescriptor<Hike>()).map(\.summary)
    }

    // MARK: - Writing

    /// Save, or put the context back as it was. A failed save must not leave its inserts
    /// pending, where the next successful save would write them after the reader was told
    /// it failed — and a retry would write them twice.
    func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Log a visit the user has just confirmed, or add to the one already logged at the
    /// place that day — one visit per place per day, however it was logged (stamped,
    /// hiked, checked in). A rating or notes given here replace the visit's own; a trip
    /// given here is joined if the visit has none.
    ///
    /// `calendar` decides "that day": the place's own zone, so a day is the day it was
    /// there.
    @discardableResult
    public func checkIn(
        to placeID: UnigridsID,
        on date: Date = Date(),
        source: VisitSource = .manual,
        rating: Int? = nil,
        notes: String = "",
        trip: Trip? = nil,
        calendar: Calendar? = nil
    ) throws -> Visit {
        let calendar = calendar ?? self.calendar
        if let visit = try visit(to: placeID, on: date, calendar: calendar) {
            if let rating {
                visit.rating = rating
            }
            if !notes.isEmpty {
                visit.notes = notes
            }
            if visit.trip == nil {
                visit.trip = try trip ?? matchingTrip(for: placeID, on: date, calendar: calendar)
            }
            try save()
            return visit
        }
        let visit = try Visit(
            placeID: placeID,
            date: date,
            source: source,
            rating: rating,
            notes: notes,
            trip: trip ?? matchingTrip(for: placeID, on: date, calendar: calendar)
        )
        context.insert(visit)
        try save()
        return visit
    }

    /// Record a check-in at a sight, visitor centre or trail inside a visit.
    @discardableResult
    public func checkIn(
        at target: CheckInTarget,
        during visit: Visit,
        on date: Date = Date(),
        notes: String = ""
    ) throws -> CheckIn {
        let checkIn = CheckIn(target: target, date: date, notes: notes)
        checkIn.visit = visit
        context.insert(checkIn)
        try save()
        return checkIn
    }

    /// Stamp a place, creating or joining the visit that the impression belongs to.
    ///
    /// Stamping is free-form (§9): any place, any date, including back-dated stamps for
    /// past trips. Whichever date the user picks, the log gains a matching visit, so the
    /// passport and the trip log can never disagree about where the user has been.
    @discardableResult
    public func stamp(
        _ placeID: UnigridsID,
        at stampLocationID: UnigridsID? = nil,
        on date: Date = Date(),
        verifiedOnSite: Bool = false,
        realStampCollected: Bool = false,
        calendar: Calendar? = nil
    ) throws -> Stamp {
        let visit = try visitOrCreate(
            for: placeID, on: date, source: .stamp, calendar: calendar ?? self.calendar
        )
        let stamp = Stamp(
            placeID: placeID,
            stampLocationID: stampLocationID,
            date: date,
            isVerifiedOnSite: verifiedOnSite,
            realStampCollected: realStampCollected,
            visit: visit
        )
        context.insert(stamp)
        try save()
        return stamp
    }

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

    /// Mark a trail hiked, which also records a check-in on the visit.
    @discardableResult
    public func markHiked(
        _ trailID: UnigridsID,
        in placeID: UnigridsID,
        on date: Date = Date(),
        completion: HikeCompletion = .full,
        calendar: Calendar? = nil
    ) throws -> Hike {
        let visit = try visitOrCreate(
            for: placeID, on: date, source: .hike, calendar: calendar ?? self.calendar
        )
        let hike = Hike(trailID: trailID, date: date, completion: completion)
        hike.visit = visit
        context.insert(hike)
        let checkIn = CheckIn(target: .trail(trailID), date: date)
        checkIn.visit = visit
        context.insert(checkIn)
        try save()
        return hike
    }

    /// Move a visit to another day, with everything logged on it. Its weather was the
    /// old day's, so it goes, and is fetched again for the new one.
    public func move(_ visit: Visit, to date: Date) throws {
        let delta = date.timeIntervalSince(visit.date)
        guard delta != 0 else { return }
        visit.date = date
        visit.endDate = visit.endDate?.addingTimeInterval(delta)
        for checkIn in visit.checkIns ?? [] {
            checkIn.date = checkIn.date.addingTimeInterval(delta)
        }
        for hike in visit.hikes ?? [] {
            hike.date = hike.date.addingTimeInterval(delta)
        }
        for stamp in visit.stamps ?? [] {
            stamp.date = stamp.date.addingTimeInterval(delta)
        }
        if let weather = visit.weather {
            context.delete(weather)
            visit.weather = nil
        }
        try save()
    }

    @discardableResult
    public func createTrip(
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        status: TripStatus = .planned
    ) throws -> Trip {
        let trip = Trip(name: name, startDate: startDate, endDate: endDate, status: status)
        context.insert(trip)
        try save()
        return trip
    }

    /// Add a place to a trip's itinerary, at the end. A place already on the trip is left
    /// where it is rather than listed twice.
    @discardableResult
    public func addStop(
        _ placeID: UnigridsID,
        to trip: Trip,
        on date: Date? = nil,
        target: StopTarget = .place
    ) throws -> TripStop {
        if let existing = trip.orderedStops.first(where: {
            $0.place == placeID && $0.target == target
        }) {
            return existing
        }
        let stop = TripStop(
            placeID: placeID,
            order: (trip.orderedStops.last?.order ?? -1) + 1,
            plannedDate: date,
            target: target
        )
        stop.trip = trip
        context.insert(stop)
        try save()
        return stop
    }

    /// Add a reminder to a trip, kept in the zone it was set in.
    @discardableResult
    public func addReminder(
        kind: Reminder.Kind,
        on date: Date,
        title: String,
        url: URL?,
        timeZone: TimeZone = .current,
        to trip: Trip
    ) throws -> Reminder {
        let reminder = Reminder(
            kind: kind, date: date, title: title, url: url, timeZone: timeZone, trip: trip
        )
        context.insert(reminder)
        try save()
        return reminder
    }

    /// Put a trip's stops in a new order.
    public func reorder(_ stops: [TripStop]) throws {
        for (index, stop) in stops.enumerated() {
            stop.order = index
        }
        try save()
    }

    /// The ids of places on trips that have not finished, for the map's planned styling.
    public func plannedPlaceIDs(now: Date = Date()) throws -> Set<UnigridsID> {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        return Set(
            trips
                .filter { $0.status(on: now) != .done }
                .flatMap { ($0.stops ?? []).map(\.place) }
        )
    }

    public func attach(_ weather: WeatherSnapshot, to visit: Visit) throws {
        weather.visit = visit
        context.insert(weather)
        try save()
    }

    public func update(_ body: () -> Void) throws {
        body()
        try save()
    }

    /// Delete every record in the log. For the reader who asks, after a confirmation;
    /// there is no undo.
    public func eraseEverything() throws {
        try context.delete(model: Stamp.self)
        try context.delete(model: Hike.self)
        try context.delete(model: CheckIn.self)
        try context.delete(model: WeatherSnapshot.self)
        try context.delete(model: Visit.self)
        try context.delete(model: TripStop.self)
        try context.delete(model: Reminder.self)
        try context.delete(model: Trip.self)
        try save()
    }

    // MARK: - Private

    /// The visit to `placeID` on the day `date` falls on in `calendar`, if one is logged.
    public func visit(to placeID: UnigridsID, on date: Date, calendar: Calendar) throws -> Visit? {
        try visits(to: placeID).first { visit in
            UnigridsCalendar.isSameDay(visit.date, date, calendar: calendar)
        }
    }

    /// The visit a stamp or hike on `date` belongs to, creating one if there is none.
    ///
    /// "Same visit" means the same place on the same calendar day, there. A second
    /// impression on a later date is a second visit, which is what the paper book records
    /// too.
    private func visitOrCreate(
        for placeID: UnigridsID,
        on date: Date,
        source: VisitSource,
        calendar: Calendar
    ) throws -> Visit {
        if let existing = try visit(to: placeID, on: date, calendar: calendar) {
            if existing.trip == nil {
                existing.trip = try matchingTrip(for: placeID, on: date, calendar: calendar)
            }
            return existing
        }
        let visit = try Visit(
            placeID: placeID,
            date: date,
            source: source,
            trip: matchingTrip(for: placeID, on: date, calendar: calendar)
        )
        context.insert(visit)
        return visit
    }

    /// The trip a visit logged without one belongs to, by `TripMatching`'s rule.
    private func matchingTrip(
        for placeID: UnigridsID,
        on date: Date,
        calendar: Calendar
    ) throws -> Trip? {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let candidates = trips.map { trip in
            TripMatching.Candidate(
                id: trip.id,
                start: trip.startDate,
                end: trip.endDate,
                status: trip.status,
                listsPlace: (trip.stops ?? []).contains { $0.place == placeID }
            )
        }
        let id = TripMatching.trip(for: date, among: candidates, calendar: calendar)
        return trips.first { $0.id == id }
    }
}
