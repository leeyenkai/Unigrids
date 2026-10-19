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
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
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

    /// Log a visit the user has just confirmed.
    @discardableResult
    public func checkIn(
        to placeID: UnigridsID,
        on date: Date = Date(),
        source: VisitSource = .manual,
        rating: Int? = nil,
        notes: String = "",
        trip: Trip? = nil
    ) throws -> Visit {
        let visit = Visit(
            placeID: placeID,
            date: date,
            source: source,
            rating: rating,
            notes: notes,
            trip: trip
        )
        context.insert(visit)
        try context.save()
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
        try context.save()
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
        realStampCollected: Bool = false
    ) throws -> Stamp {
        let visit = try visitOrCreate(for: placeID, on: date)
        let stamp = Stamp(
            placeID: placeID,
            stampLocationID: stampLocationID,
            date: date,
            isVerifiedOnSite: verifiedOnSite,
            realStampCollected: realStampCollected,
            visit: visit
        )
        context.insert(stamp)
        try context.save()
        return stamp
    }

    /// Mark a trail hiked, which also records a check-in on the visit.
    @discardableResult
    public func markHiked(
        _ trailID: UnigridsID,
        in placeID: UnigridsID,
        on date: Date = Date(),
        completion: HikeCompletion = .full
    ) throws -> Hike {
        let visit = try visitOrCreate(for: placeID, on: date)
        let hike = Hike(trailID: trailID, date: date, completion: completion)
        hike.visit = visit
        context.insert(hike)
        let checkIn = CheckIn(target: .trail(trailID), date: date)
        checkIn.visit = visit
        context.insert(checkIn)
        try context.save()
        return hike
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
        try context.save()
        return trip
    }

    /// Add a place to a trip's itinerary, at the end. A place already on the trip is left
    /// where it is rather than listed twice.
    @discardableResult
    public func addStop(
        _ placeID: UnigridsID,
        to trip: Trip,
        on date: Date? = nil
    ) throws -> TripStop {
        if let existing = trip.orderedStops.first(where: { $0.place == placeID }) {
            return existing
        }
        let stop = TripStop(
            placeID: placeID,
            order: (trip.orderedStops.last?.order ?? -1) + 1,
            plannedDate: date
        )
        stop.trip = trip
        context.insert(stop)
        try context.save()
        return stop
    }

    /// Put a trip's stops in a new order.
    public func reorder(_ stops: [TripStop]) throws {
        for (index, stop) in stops.enumerated() {
            stop.order = index
        }
        try context.save()
    }

    /// The ids of places on trips that have not finished, for the map's planned styling.
    public func plannedPlaceIDs() throws -> Set<UnigridsID> {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        return Set(
            trips
                .filter { $0.status != .done }
                .flatMap { ($0.stops ?? []).map(\.place) }
        )
    }

    public func attach(_ weather: WeatherSnapshot, to visit: Visit) throws {
        weather.visit = visit
        context.insert(weather)
        try context.save()
    }

    public func update(_ body: () -> Void) throws {
        body()
        try context.save()
    }

    /// Delete a record. Cascades follow the relationships declared on the models, so
    /// deleting a visit takes its check-ins, hikes and weather with it — but leaves its
    /// stamps, which the user may well want to keep.
    public func delete(_ model: some PersistentModel) throws {
        context.delete(model)
        try context.save()
    }

    // MARK: - Private

    /// The visit a stamp or hike on `date` belongs to, creating one if there is none.
    ///
    /// "Same visit" means the same place on the same calendar day. A second impression on
    /// a later date is a second visit, which is what the paper book records too.
    private func visitOrCreate(for placeID: UnigridsID, on date: Date) throws -> Visit {
        let existing = try visits(to: placeID).first { visit in
            calendar.isDate(visit.date, inSameDayAs: date)
        }
        if let existing {
            return existing
        }

        let visit = Visit(placeID: placeID, date: date, source: .stamp)
        context.insert(visit)
        return visit
    }
}
