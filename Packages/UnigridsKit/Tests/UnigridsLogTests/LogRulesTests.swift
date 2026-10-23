import Foundation
import SwiftData
import Testing
import UnigridsCore
@testable import UnigridsLog

/// The rules that keep the log one consistent record: one visit per place per day, the
/// passport and the log agreeing, trips gathering their visits, and every change
/// undoable.
@MainActor
@Suite("Log rules")
struct LogRulesTests {
    private let container: ModelContainer
    private let store: LogStore
    private let calendar: Calendar

    init() throws {
        container = try UnigridsModelContainer.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        self.calendar = calendar
        store = LogStore(context: ModelContext(container), calendar: calendar)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? Date()
    }

    // MARK: - One visit per place per day

    @Test("checking in on a day already stamped joins that visit")
    func checkInJoinsStampedVisit() throws {
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 1, hour: 9))
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1, hour: 15), rating: 4)
        #expect(stamp.visit?.id == visit.id)
        #expect(try store.visits().count == 1)
        #expect(visit.rating == 4)
    }

    @Test("a hike starts a visit that says it was a hike")
    func hikeVisitSource() throws {
        try store.markHiked("trail-zion-watchman-trail", in: "np-zion", on: date(2026, 5, 1))
        #expect(try store.visits().first?.source == .hike)
    }

    @Test("a day is the day at the place: late evening in Hawaii is one visit")
    func dayAtThePlace() throws {
        let hawaii = UnigridsCalendar.gregorian(TimeZone(identifier: "Pacific/Honolulu") ?? .gmt)
        // 20:00 and 23:30 Hawaii time on 4 July straddle midnight UTC.
        let evening = try #require(hawaii.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 4,
            hour: 20
        )))
        let late = try #require(hawaii.date(from: DateComponents(
            year: 2026, month: 7, day: 4, hour: 23, minute: 30
        )))
        try store.checkIn(to: "np-haleakala", on: evening, calendar: hawaii)
        try store.stamp("np-haleakala", on: late, calendar: hawaii)
        #expect(try store.visits().count == 1)
    }

    // MARK: - Trips

    @Test("a stamp joins the dated trip that lists the place and covers the day")
    func stampJoinsCoveringTrip() throws {
        let trip = try store.createTrip(
            name: "Utah",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 6)
        )
        try store.addStop("np-zion", to: trip)
        let other = try store.createTrip(
            name: "Later",
            startDate: date(2026, 9, 1),
            endDate: date(2026, 9, 3)
        )
        try store.addStop("np-zion", to: other)
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 3))
        #expect(stamp.visit?.trip?.id == trip.id)
    }

    @Test("a back-dated stamp with no covering trip stays loose")
    func backDatedStampStaysLoose() throws {
        let trip = try store.createTrip(name: "Someday")
        try store.addStop("np-zion", to: trip)
        let stamp = try store.stamp("np-zion", on: date(2019, 5, 3))
        #expect(stamp.visit?.trip == nil)
    }

    @Test("a trip's status follows its dates")
    func tripStatusFromDates() throws {
        let trip = try store.createTrip(
            name: "Utah",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 6)
        )
        #expect(trip.status(on: date(2026, 4, 30), calendar: calendar) == .planned)
        #expect(trip.status(on: date(2026, 5, 6, hour: 22), calendar: calendar) == .active)
        #expect(trip.status(on: date(2026, 5, 7), calendar: calendar) == .done)
        let undated = try store.createTrip(name: "Someday", status: .done)
        #expect(undated.status(on: date(2026, 5, 1), calendar: calendar) == .done)
    }

    // MARK: - Undo

    @Test("deleting a hike takes its check-in, and the visit it alone made")
    func hikeDeletion() throws {
        let hike = try store.markHiked(
            "trail-zion-watchman-trail",
            in: "np-zion",
            on: date(2026, 5, 1)
        )
        let change = try store.delete(hike: hike)
        #expect(try store.visits().isEmpty)
        try store.undo(change)
        let visit = try #require(try store.visits().first)
        #expect(visit.hikes?.count == 1)
        #expect(visit.checkIns?.count == 1)
    }

    @Test("deleting one hike of two keeps the visit and the other")
    func oneHikeOfTwo() throws {
        let first = try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 1, hour: 9))
        try store.markHiked("trail-b", in: "np-zion", on: date(2026, 5, 1, hour: 14))
        try store.delete(hike: first)
        let visit = try #require(try store.visits().first)
        #expect(visit.hikes?.map(\.trailID) == ["trail-b"])
        #expect(visit.checkIns?.map(\.targetID) == ["trail-b"])
    }

    @Test("a stop and a reminder taken off a trip come back to it")
    func stopAndReminderUndo() throws {
        let trip = try store.createTrip(name: "Utah")
        let stop = try store.addStop(
            "np-zion",
            to: trip,
            target: .trail("trail-zion-angels-landing")
        )
        let reminder = try store.addReminder(
            kind: .timedEntry, on: date(2026, 4, 1), title: "Lottery", url: nil, to: trip
        )
        let stopChange = try store.delete(stop: stop)
        let reminderChange = try store.delete(reminder: reminder)
        #expect(trip.orderedStops.isEmpty)
        try store.undo(stopChange)
        try store.undo(reminderChange)
        #expect(trip.orderedStops.first?.target == .trail("trail-zion-angels-landing"))
        #expect(trip.reminders?.first?.title == "Lottery")
        #expect(reminderChange.removedReminderIDs == [reminder.id])
    }

    @Test("undoing a stamp takes the visit it made")
    func stampUndo() throws {
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 1))
        try store.undo(store.undoing(stamp: stamp, madeVisit: true))
        #expect(try store.stamps().isEmpty)
        #expect(try store.visits().isEmpty)
    }

    @Test("undoing a hike takes its check-in and the visit it made, and leaves a visit it joined")
    func hikeUndo() throws {
        let hike = try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 1))
        try store.undo(store.undoing(hike: hike, madeVisit: true))
        #expect(try store.visits().isEmpty)

        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 2))
        let joined = try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 2, hour: 15))
        try store.undo(store.undoing(hike: joined, madeVisit: false))
        #expect(try store.visits().count == 1)
        #expect(visit.hikes?.isEmpty == true)
        #expect(visit.checkIns?.contains { $0.targetKindRaw == "trail" } == false)
    }

    // MARK: - Editing

    @Test("moving a visit moves everything logged on it and drops its weather")
    func moveVisit() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        try store.stamp("np-zion", on: date(2026, 5, 1))
        try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 1))
        try store.attach(
            WeatherSnapshot(date: date(2026, 5, 1), source: .openMeteoArchive),
            to: visit
        )
        try store.move(visit, to: date(2026, 5, 3))
        #expect(visit.stamps?.first.map { calendar.component(.day, from: $0.date) } == 3)
        #expect(visit.hikes?.first.map { calendar.component(.day, from: $0.date) } == 3)
        #expect(visit.weather == nil)
    }

    @Test("moving a visit onto a day with one joins it rather than making two")
    func moveVisitOntoLoggedDay() throws {
        let kept = try store.checkIn(to: "np-zion", on: date(2026, 5, 3), notes: "Narrows")
        let moved = try store.checkIn(to: "np-zion", on: date(2026, 5, 1), rating: 4)
        try store.stamp("np-zion", on: date(2026, 5, 1))
        try store.update { moved.notes = "Angels Landing" }
        let result = try store.move(moved, to: date(2026, 5, 3))
        #expect(result.id == kept.id)
        #expect(try store.visits().count == 1)
        #expect(kept.stamps?.count == 1)
        #expect(kept.stamps?.first.map { calendar.component(.day, from: $0.date) } == 3)
        #expect(kept.rating == 4)
        #expect(kept.notes == "Narrows\n\nAngels Landing")
    }

    // MARK: - Archive

    @Test("an archive merged into an empty log reproduces it, and merging again adds nothing")
    func archiveRoundTrip() throws {
        let trip = try store.createTrip(name: "Utah", startDate: date(2026, 5, 1))
        try store.addStop("np-zion", to: trip, target: .custom(
            name: "Springdale motel", location: Coordinate(latitude: 37.19, longitude: -112.99)
        ))
        try store.addReminder(
            kind: .permit,
            on: date(2026, 3, 1),
            title: "Permit",
            url: nil,
            to: trip
        )
        let visit = try store.checkIn(
            to: "np-zion",
            on: date(2026, 5, 1),
            rating: 5,
            notes: "Hot",
            trip: trip
        )
        try store.checkIn(at: .pointOfInterest("poi-zion-the-narrows"), during: visit)
        try store.stamp(
            "np-zion",
            at: "poi-zion-visitor-center",
            on: date(2026, 5, 1),
            verifiedOnSite: true
        )
        try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 1), completion: .partial)
        try store.attach(
            WeatherSnapshot(date: date(2026, 5, 1), highCelsius: 35, source: .openMeteoArchive),
            to: visit
        )

        var original = try store.archive()
        let decoded = try LogArchive.decode(original.json())

        let elsewhere = try LogStore(
            context: ModelContext(UnigridsModelContainer.inMemory()),
            calendar: calendar
        )
        let summary = try elsewhere.merge(decoded)
        #expect(summary.visitsAdded == 1 && summary.tripsAdded == 1 && summary.stampsAdded == 1)
        // What the reader gets back: the copy's export reads exactly as the original's.
        var copied = try elsewhere.archive()
        original.exportedAt = .distantPast
        copied.exportedAt = .distantPast
        #expect(try copied.json() == original.json())
        #expect(copied.stamps.first?.stampLocationID == "poi-zion-visitor-center")
        #expect(copied.trips.first?.stops.first?.customName == "Springdale motel")

        let again = try elsewhere.merge(decoded)
        #expect(again.added == 0)
    }

    @Test("a backup's visit on a day the log already has joins that visit")
    func mergeJoinsSameDayVisit() throws {
        let here = try store.checkIn(to: "np-acadia", on: date(2025, 9, 14, hour: 9))
        let elsewhere = try LogStore(
            context: ModelContext(UnigridsModelContainer.inMemory()),
            calendar: calendar
        )
        let there = try elsewhere.checkIn(to: "np-acadia", on: date(2025, 9, 14, hour: 16))
        try elsewhere.markHiked("trail-acadia-beehive", in: "np-acadia", on: there.date)
        try elsewhere.stamp("np-acadia", on: there.date)

        let summary = try store.merge(elsewhere.archive())
        #expect(try store.visits().count == 1)
        #expect(here.hikes?.count == 1 && here.stamps?.count == 1)
        #expect(summary.visitsAdded == 0 && summary.stampsAdded == 1)
        // The hike and its trail check-in: added, and counted, though no visit was.
        #expect(summary.othersAdded == 2 && summary.added == 3)
    }

    @Test("a first-version export still imports what it holds")
    func legacyImport() throws {
        let legacy = Data(#"""
        {"exportedAt": "2026-01-02T03:04:05Z",
         "visits": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "placeID": "np-zion",
                     "placeName": "Zion", "date": "2025-05-01T12:00:00Z", "source": "manual",
                     "rating": 4, "notes": "", "trip": null, "checkIns": []}],
         "stamps": [{"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "placeID": "np-zion",
                     "placeName": "Zion", "date": "2025-05-01T12:00:00Z", "verifiedOnSite": false,
                     "realStampCollected": true, "america250": false}],
         "trips": []}
        """#.utf8)
        let archive = try LogArchive.decode(legacy)
        #expect(archive.version == 1)
        let summary = try store.merge(archive)
        #expect(summary.visitsAdded == 1 && summary.stampsAdded == 1)
        #expect(try store.stamps().first?.visit?.placeID == "np-zion")
    }

    /// Every attribute the store keeps must be in the archive, or export, import and undo
    /// silently drop it. A new model field fails here until it is archived.
    @Test("the archive carries every stored attribute")
    func archiveCoversTheSchema() throws {
        let renamed: [String: String] = [
            "statusRaw": "status", "sourceRaw": "source", "targetKindRaw": "targetKind",
            "completionRaw": "completion", "kindRaw": "kind", "urlString": "url",
        ]
        // Links the archive keeps as identifiers or by nesting rather than as attributes.
        let relationships: Set = [
            "trip", "visit", "visits", "stops", "reminders", "checkIns", "hikes", "stamps",
            "weather",
        ]
        // Every optional filled: JSON leaves a nil out, and a left-out key proves nothing.
        let trip = try store.createTrip(
            name: "T",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 3)
        )
        let stop = try store.addStop(
            "np-zion", to: trip, on: date(2026, 5, 1),
            target: .custom(name: "Motel", location: Coordinate(latitude: 37, longitude: -113))
        )
        stop.notes = "Late check-in"
        try store.addReminder(
            kind: .permit, on: date(2026, 3, 1), title: "R",
            url: URL(string: "https://www.recreation.gov"),
            to: trip
        )
        let visit = try store.checkIn(
            to: "np-zion",
            on: date(2026, 5, 1),
            rating: 4,
            notes: "N",
            trip: trip
        )
        visit.endDate = date(2026, 5, 2)
        try store.stamp("np-zion", at: "poi-zion-visitor-center", on: date(2026, 5, 1))
        try store.markHiked("trail-a", in: "np-zion", on: date(2026, 5, 1))
        try store.attach(
            WeatherSnapshot(
                date: date(2026, 5, 1), highCelsius: 30, lowCelsius: 12,
                precipitationMillimetres: 0, condition: "Clear", source: .openMeteoArchive
            ),
            to: visit
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: store.archive().json()) as? [String: Any]
        )
        func keys(_ value: Any?) -> Set<String> {
            if let object = value as? [String: Any] {
                return Set(object.keys).union(object.values.flatMap { keys($0) })
            }
            if let array = value as? [Any] {
                return array.reduce(into: []) { $0.formUnion(keys($1)) }
            }
            return []
        }
        let archived = keys(json)
        for entity in UnigridsSchema.schema.entities {
            for attribute in entity.attributes where !relationships.contains(attribute.name) {
                let name = renamed[attribute.name] ?? attribute.name
                #expect(archived.contains(name), "\(entity.name).\(attribute.name) is not archived")
            }
        }
    }
}
