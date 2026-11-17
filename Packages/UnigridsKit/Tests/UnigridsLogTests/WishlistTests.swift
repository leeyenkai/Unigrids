import Foundation
import SwiftData
import Testing
import UnigridsCore
@testable import UnigridsLog

/// The wishlist: one wish per place, kept in backups, merged without duplicates, and
/// erased with everything else.
@MainActor
@Suite("Wishlist")
struct WishlistTests {
    private let store: LogStore

    init() throws {
        store = try LogStore(context: ModelContext(UnigridsModelContainer.inMemory()))
    }

    @Test("toggling puts a place on the list once, and takes it off again")
    func toggle() throws {
        #expect(try store.toggleWish("np-zion"))
        #expect(try store.wishes().map(\.placeID) == ["np-zion"])
        #expect(try !store.toggleWish("np-zion"))
        #expect(try store.wishes().isEmpty)
    }

    @Test("a backup keeps the wishlist, and merging it twice adds nothing twice")
    func backup() throws {
        try store.toggleWish("jp-np-shiretoko")
        let archive = try LogArchive.decode(store.archive().json())
        #expect(archive.wishes.map(\.placeID) == ["jp-np-shiretoko"])

        let elsewhere = try LogStore(context: ModelContext(UnigridsModelContainer.inMemory()))
        try elsewhere.toggleWish("jp-np-shiretoko")
        let summary = try elsewhere.merge(archive)
        #expect(summary.othersAdded == 0 && summary.alreadyPresent == 1)

        let empty = try LogStore(context: ModelContext(UnigridsModelContainer.inMemory()))
        #expect(try empty.merge(archive).othersAdded == 1)
        #expect(try empty.merge(archive).othersAdded == 0)
        #expect(try empty.wishes().count == 1)
    }

    @Test("a backup from before the wishlist still reads, with none")
    func olderBackup() throws {
        let older = Data(#"""
        {"version": 2, "exportedAt": "2026-01-02T03:04:05.000Z",
         "trips": [], "visits": [], "stamps": []}
        """#.utf8)
        let archive = try LogArchive.decode(older)
        #expect(archive.version == 2 && archive.wishes.isEmpty)
    }

    @Test("erasing the log erases the wishlist")
    func erase() throws {
        try store.toggleWish("no-np-jotunheimen")
        try store.eraseEverything()
        #expect(try store.wishes().isEmpty)
    }
}
