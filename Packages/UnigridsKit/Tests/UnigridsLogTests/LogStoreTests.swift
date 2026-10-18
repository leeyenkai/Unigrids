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
        #expect(UnigridsSchema.models.count == 7)
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

    @Test("deleting a visit takes its check-ins but keeps its stamps")
    func deleteCascades() throws {
        let visit = try store.checkIn(to: "np-zion", on: date(2026, 5, 1))
        try store.checkIn(at: .pointOfInterest("poi-zion-the-narrows"), during: visit)
        try store.stamp("np-zion", on: date(2026, 5, 1))

        try store.delete(visit)

        #expect(try store.visits().isEmpty)
        // The impression is the user's record of having been there; losing it with the
        // visit would be a surprise, so the relationship nullifies rather than cascades.
        #expect(try store.stamps().count == 1)
        #expect(try store.stamps().first?.visit == nil)
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
}
