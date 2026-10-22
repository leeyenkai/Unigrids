import Foundation
import SwiftData
import Testing
import UnigridsCore
@testable import UnigridsLog

@MainActor
@Suite("Log store")
struct LogStoreTests {
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
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? Date()
    }

    @Test("the schema initialises in memory")
    func schemaLoads() {
        #expect(UnigridsSchema.models.count == 8)
    }

    @Test("a check-in creates a visit")
    func checkInCreatesVisit() throws {
        try store.checkIn(to: "np-zion", on: date(2026, 5, 1), rating: 5, notes: "Hot")
        let visits = try store.visits()
        #expect(visits.count == 1)
        #expect(visits.first?.place == "np-zion")
        #expect(visits.first?.rating == 5)
        #expect(visits.first?.source == .manual)
        #expect(try store.isVisited("np-zion"))
        #expect(try !store.isVisited("np-acadia"))
    }

    @Test("stamping a place also puts a visit in the log")
    func stampCreatesVisit() throws {
        // §9: "Stamping creates or joins a visit in the log, so the passport and the trip
        // log always agree."
        let stamp = try store.stamp("np-acadia", on: date(2026, 7, 4))
        #expect(stamp.visit != nil)
        #expect(try store.visits().count == 1)
        #expect(try store.visits().first?.source == .stamp)
    }

    @Test("a stamp on a day already visited joins that visit")
    func stampJoinsSameDayVisit() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1, hour: 9))
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 1, hour: 17))
        #expect(stamp.visit?.id == visit.id)
        #expect(try store.visits().count == 1)
    }

    @Test("a stamp on a different day is a different visit")
    func stampOnAnotherDayIsAnotherVisit() throws {
        try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        try store.stamp("np-zion", on: date(2026, 9, 14))
        #expect(try store.visits().count == 2)
        #expect(try store.stamps(for: "np-zion").count == 1)
    }

    @Test("a back-dated stamp is allowed, and dated when the user says")
    func backDatedStampsAreAllowed() throws {
        // Stamping is free-form: any place, any date, including trips from years ago.
        let stamp = try store.stamp("np-yellowstone", on: date(2019, 8, 2))
        #expect(stamp.date == date(2019, 8, 2))
        #expect(!stamp.hasAmerica250Seal(calendar: calendar))
    }

    @Test("a 2026 stamp earns the America 250 seal and a 2025 one does not")
    func america250SealIsDerived() throws {
        let in2026 = try store.stamp("np-zion", on: date(2026, 3, 1))
        let in2025 = try store.stamp("np-acadia", on: date(2025, 3, 1))
        #expect(in2026.hasAmerica250Seal(calendar: calendar))
        #expect(!in2025.hasAmerica250Seal(calendar: calendar))
    }

    @Test("a stamp's impression survives a round trip through the store")
    func seedRoundTrips() throws {
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 1))
        let seed = stamp.seed
        let impression = stamp.impression

        let refetched = try #require(try store.stamps(for: "np-zion").first)
        #expect(refetched.seed == seed)
        #expect(refetched.impression == impression)
    }

    @Test("a large seed round-trips through Int64 storage without loss")
    func largeSeedRoundTrips() {
        let stamp = Stamp(placeID: "np-zion", seed: UInt64.max)
        #expect(stamp.seed == UInt64.max)
        let another = Stamp(placeID: "np-zion", seed: 0)
        #expect(another.seed == 0)
    }

    @Test("marking a trail hiked records the hike and a check-in")
    func markHiked() throws {
        try store.markHiked(
            "trail-zion-angels-landing",
            in: "np-zion",
            on: date(2026, 5, 2),
            completion: .partial
        )
        let visit = try #require(try store.visits().first)
        #expect(visit.hikes?.count == 1)
        #expect(visit.checkIns?.count == 1)
        #expect(try store.hikeSummaries().first?.completion == .partial)
    }

    @Test("a visit can belong to a trip")
    func visitJoinsTrip() throws {
        let trip = try store.createTrip(name: "Utah 2026", status: .planned)
        try store.checkIn(to: "np-zion", on: date(2026, 5, 1), trip: trip)
        try store.checkIn(to: "np-bryce-canyon", on: date(2026, 5, 3), trip: trip)
        #expect(trip.visits?.count == 2)
    }

    @Test("deleting a visit takes everything on it, its stamps included")
    func deleteCascades() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        try store.checkIn(at: .pointOfInterest("poi-zion-the-narrows"), during: visit)
        try store.stamp("np-zion", on: date(2026, 5, 1))

        let change = try store.delete(visit: visit)

        // The passport and the log agree: a stamp is the record of a visit, and one left
        // behind would say "been" where the map says "not".
        #expect(try store.visits().isEmpty)
        #expect(try store.stamps().isEmpty)
        #expect(change.subject == .visit("np-zion", stamps: 1))
    }

    @Test("visit summaries feed the stats without the stats knowing about SwiftData")
    func summariesForStats() throws {
        try store.checkIn(to: "np-zion", on: date(2024, 5, 1))
        try store.checkIn(to: "np-acadia", on: date(2026, 9, 1))
        let summaries = try store.visitSummaries()
        let report = StatsReport(
            places: [],
            visits: summaries,
            calendar: calendar
        )
        #expect(report.totalVisits == 2)
        #expect(report.visitsByYear.map(\.year) == [2024, 2026])
    }

    @Test("weather attaches to a visit and records its source")
    func weatherSnapshot() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        let weather = WeatherSnapshot(
            date: date(2026, 5, 1),
            highCelsius: 31,
            lowCelsius: 14,
            condition: "Clear",
            source: .weatherKit
        )
        try store.attach(weather, to: visit)
        #expect(visit.weather?.highCelsius == 31)
        #expect(visit.weather?.source == .weatherKit)
    }

    @Test("an unknown stored enum value degrades instead of failing")
    func unknownRawValuesDegrade() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        try store.update { visit.sourceRaw = "teleportation" }
        #expect(visit.source == .manual)
    }

    @Test("a trip's stops keep their order and a place is not added twice")
    func tripStops() throws {
        let trip = try store.createTrip(name: "Utah in April")
        try store.addStop("np-zion", to: trip)
        try store.addStop("np-bryce-canyon", to: trip)
        try store.addStop("np-zion", to: trip)
        #expect(trip.orderedStops.map(\.place) == ["np-zion", "np-bryce-canyon"])

        try store.reorder(trip.orderedStops.reversed())
        #expect(trip.orderedStops.map(\.place) == ["np-bryce-canyon", "np-zion"])
    }

    @Test("a planned stop is planned, never visited")
    func plannedIsNotVisited() throws {
        let trip = try store.createTrip(name: "Someday")
        try store.addStop("np-denali", to: trip)
        #expect(try store.plannedPlaceIDs() == ["np-denali"])
        #expect(try !store.isVisited("np-denali"))

        trip.status = .done
        #expect(try store.plannedPlaceIDs().isEmpty)
    }

    @Test("the export carries every visit, stamp and trip, by id and by name")
    func export() throws {
        let trip = try store.createTrip(name: "Coast, \"north\"")
        try store.checkIn(to: "np-acadia", on: date(2026, 7, 4), notes: "Fog, then sun", trip: trip)
        try store.stamp("np-acadia", on: date(2026, 7, 4))
        try store.addStop("np-acadia", to: trip)

        let archive = try store.archive(
            name: { $0 == "np-acadia" ? "Acadia" : nil },
            calendar: { _ in calendar }
        )
        #expect(archive.visits.count == 1)
        #expect(archive.visits.first?.placeName == "Acadia")
        #expect(archive.stamps.first?.america250 == true)
        #expect(archive.trips.first?.stops.map(\.placeID) == ["np-acadia"])

        let decoded = try LogArchive.decode(archive.json())
        #expect(decoded.visits.count == 1)

        let csv = LogExport.visitsCSV(archive) { _ in calendar }
        #expect(csv.hasPrefix("date,place,place_id,source,rating,notes\r\n"))
        #expect(csv.contains("2026-07-04,Acadia,np-acadia"))
        // A comma in the notes is quoted, not taken as a column.
        #expect(csv.contains("\"Fog, then sun\""))
    }

    @Test("CSV quoting follows RFC 4180, line breaks of every kind included")
    func csvQuoting() {
        #expect(LogExport.csvField("plain") == "plain")
        #expect(LogExport.csvField("a,b") == "\"a,b\"")
        #expect(LogExport.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
        // "\r\n" is one Character in Swift, neither "\r" nor "\n".
        #expect(LogExport.csvField("a\r\nb") == "\"a\r\nb\"")
        #expect(LogExport.csvField("a\nb") == "\"a\nb\"")
    }

    @Test("a CSV field that starts like a formula is not one")
    func csvFormulaGuard() {
        #expect(LogExport.csvField("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(LogExport.csvField("+1 day") == "'+1 day")
        #expect(LogExport.csvField("-") == "'-")
    }

    @Test("a CSV visit is dated by its day where it happened")
    func csvLocalDay() throws {
        // 19:00 in Utah on 4 July is 01:00 UTC on 5 July.
        let utah = try #require(TimeZone(identifier: "America/Denver"))
        var utahCalendar = Calendar(identifier: .gregorian)
        utahCalendar.timeZone = utah
        let evening = try #require(utahCalendar.date(from: DateComponents(
            year: 2026, month: 7, day: 4, hour: 19
        )))
        try store.checkIn(to: "np-zion", on: evening, calendar: utahCalendar)
        let csv = try LogExport.visitsCSV(store.archive()) { _ in utahCalendar }
        #expect(csv.contains("2026-07-04,"))
    }

    @Test("a deleted visit comes back with its check-ins, hikes, stamps and trip")
    func undoVisitDeletion() throws {
        let trip = try store.createTrip(name: "Utah")
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1), trip: trip)
        try store.checkIn(at: .pointOfInterest("poi-zion-angels-landing"), during: visit)
        let stamp = try store.stamp("np-zion", on: date(2026, 5, 1))
        try store.markHiked("trail-zion-watchman-trail", in: "np-zion", on: date(2026, 5, 1))
        let originalID = visit.id
        let seed = stamp.seed
        #expect(stamp.visit?.id == originalID)

        let change = try store.delete(visit: visit)
        #expect(try store.visits().isEmpty)
        #expect(try store.stamps().isEmpty)

        try store.undo(change)
        let restored = try #require(try store.visits().first)
        #expect(restored.id == originalID)
        #expect(restored.trip?.id == trip.id)
        #expect(restored.checkIns?.count == 2)
        #expect(restored.hikes?.count == 1)
        #expect(try store.stamps().first?.visit?.id == originalID)
        #expect(try store.stamps().first?.seed == seed)
    }

    @Test("a deleted trip comes back with its stops, and its visits rejoin it")
    func undoTripDeletion() throws {
        let trip = try store.createTrip(name: "Utah")
        try store.addStop("np-zion", to: trip)
        try store.addStop("np-arches", to: trip)
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1), trip: trip)
        let change = try store.delete(trip: trip)
        #expect(try store.trips().isEmpty)
        #expect(visit.trip == nil)
        try store.undo(change)
        let restored = try #require(try store.trips().first)
        #expect(restored.orderedStops.map(\.place) == ["np-zion", "np-arches"])
        #expect(try store.visits().first?.trip?.id == restored.id)
    }

    @Test("a deleted stamp comes back with its impression unchanged")
    func undoStampDeletion() throws {
        let stamp = try store.stamp("np-acadia", on: date(2026, 7, 4))
        let seed = stamp.seed
        let change = try store.delete(stamp: stamp)
        #expect(try store.stamps().isEmpty)
        // The visit stamping made held nothing else, so it went with the stamp.
        #expect(try store.visits().isEmpty)
        try store.undo(change)
        #expect(try store.stamps().first?.seed == seed)
        #expect(try store.stamps().first?.visit != nil)
        #expect(try store.visits().count == 1)
    }

    @Test("deleting a stamp keeps a visit that holds more than the stamp")
    func stampDeletionKeepsAFullVisit() throws {
        let visit = try store.checkIn(to: "np-acadia", on: date(2026, 7, 4), notes: "Fog")
        let stamp = try store.stamp("np-acadia", on: date(2026, 7, 4))
        #expect(stamp.visit?.id == visit.id)
        try store.delete(stamp: stamp)
        #expect(try store.visits().count == 1)
    }
}
