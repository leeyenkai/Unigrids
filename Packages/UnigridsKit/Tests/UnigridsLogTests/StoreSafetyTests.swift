import Foundation
import SQLite3
import SwiftData
import Testing
import UnigridsCore
@testable import UnigridsLog

/// The log is the one thing the app must never lose. These tests hold the two ways it
/// could: a model change the existing store cannot open under, and a store moved, or not
/// moved, from where an earlier build left it.
@MainActor
@Suite("Store safety")
struct StoreSafetyTests {
    /// `Fixtures/baseline/`: a store written by the schema as it stood before the
    /// production pass (dataset of record: commit 9504ff4). Regenerate only on purpose,
    /// with `UNIGRIDS_WRITE_STORE_FIXTURE=1 swift test --filter writeBaselineFixture`.
    private static let fixtureDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/baseline", directoryHint: .isDirectory)

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "unigrids-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test(
        "write the baseline fixture",
        .enabled(if: ProcessInfo.processInfo.environment["UNIGRIDS_WRITE_STORE_FIXTURE"] != nil)
    )
    func writeBaselineFixture() throws {
        let directory = Self.fixtureDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try UnigridsModelContainer
            .local(at: directory.appending(path: "Unigrids.store"))
        let context = ModelContext(container)
        let trip = Trip(name: "Utah parks", startDate: Date(timeIntervalSince1970: 1_780_000_000))
        context.insert(trip)
        let stop = TripStop(placeID: "np-zion", order: 0, notes: "Angels Landing permit")
        stop.trip = trip
        context.insert(stop)
        let visit = Visit(
            placeID: "np-zion", date: Date(timeIntervalSince1970: 1_780_100_000), rating: 5,
            notes: "Hot", trip: trip
        )
        context.insert(visit)
        let checkIn = CheckIn(target: .trail("trail-zion-angels-landing"))
        checkIn.visit = visit
        context.insert(checkIn)
        let hike = Hike(trailID: "trail-zion-angels-landing", completion: .partial)
        hike.visit = visit
        context.insert(hike)
        context.insert(Stamp(
            placeID: "np-zion",
            stampLocationID: "poi-zion-zion-canyon-visitor-center",
            seed: 42,
            isVerifiedOnSite: true,
            visit: visit
        ))
        context.insert(Reminder(
            kind: .timedEntry,
            date: Date(timeIntervalSince1970: 1_779_000_000),
            title: "Angels Landing lottery",
            trip: trip
        ))
        let weather = WeatherSnapshot(
            date: visit.date,
            highCelsius: 36,
            lowCelsius: 20,
            source: .openMeteoArchive
        )
        weather.visit = visit
        context.insert(weather)
        try context.save()
    }

    @Test("a store written by the baseline schema opens under the current one, intact")
    func baselineStoreOpens() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.fixtureDirectory, includingPropertiesForKeys: nil
        )
        try #require(!files.isEmpty, "the baseline fixture is missing")
        let directory = try Self.temporaryDirectory()
        for file in files {
            try FileManager.default.copyItem(
                at: file, to: directory.appending(path: file.lastPathComponent)
            )
        }
        let container = try UnigridsModelContainer
            .local(at: directory.appending(path: "Unigrids.store"))
        let context = ModelContext(container)
        let visits = try context.fetch(FetchDescriptor<Visit>())
        let visit = try #require(visits.first)
        #expect(visits.count == 1)
        #expect(visit.placeID == "np-zion")
        #expect(visit.rating == 5)
        #expect(visit.trip?.name == "Utah parks")
        #expect(visit.checkIns?.count == 1)
        #expect(visit.hikes?.first?.completion == .partial)
        #expect(visit.stamps?.first?.seed == 42)
        #expect(visit.stamps?.first?.stampLocationID == "poi-zion-zion-canyon-visitor-center")
        #expect(visit.weather?.highCelsius == 36)
        #expect(try context.fetch(FetchDescriptor<TripStop>()).first?
            .notes == "Angels Landing permit")
        #expect(try context.fetch(FetchDescriptor<Reminder>()).first?.kind == .timedEntry)
    }

    @Test("a log at SwiftData's default location moves to the app's own, once")
    func movesTheDefaultStore() throws {
        let directory = try Self.temporaryDirectory()
        let source = directory.appending(path: "default.store")
        let destination = directory.appending(path: "Unigrids/Unigrids.store")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // A closed store, as the default one is at launch: the baseline fixture.
        try FileManager.default.copyItem(
            at: Self.fixtureDirectory.appending(path: "Unigrids.store"), to: source
        )
        try StoreMigration.moveDefaultStoreIfNeeded(to: destination, from: source)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let moved = try UnigridsModelContainer.local(at: destination)
        #expect(try ModelContext(moved).fetch(FetchDescriptor<Visit>()).first?.placeID == "np-zion")
    }

    @Test("another app's default store is left exactly where it is")
    func leavesOtherAppsAlone() throws {
        let directory = try Self.temporaryDirectory()
        let source = directory.appending(path: "default.store")
        var database: OpaquePointer?
        #expect(sqlite3_open(source.path, &database) == SQLITE_OK)
        sqlite3_exec(database, "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY)", nil, nil, nil)
        sqlite3_close(database)
        let destination = directory.appending(path: "Unigrids.store")
        try StoreMigration.moveDefaultStoreIfNeeded(to: destination, from: source)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
