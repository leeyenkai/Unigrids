import Foundation
import SwiftData
import UnigridsCore

/// A place the reader wants to visit: the wishlist (SPECIFICATION.md §9). One per place,
/// pointing at it by identifier like every other record in the log.
@Model
public final class Wish {
    public private(set) var id: UUID = UUID()
    public var placeID: String = ""
    public var note: String = ""
    public var createdAt: Date = Date()

    public var place: UnigridsID {
        UnigridsID(placeID)
    }

    public init(placeID: UnigridsID, note: String = "") {
        id = UUID()
        self.placeID = placeID.rawValue
        self.note = note
        createdAt = Date()
    }

    func restoreIdentity(_ id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

public struct WishArchive: Codable, Sendable, Equatable {
    public var id: UUID
    public var placeID: String
    public var placeName: String?
    public var note: String
    public var createdAt: Date
}

extension WishArchive {
    init(_ wish: Wish, name: (UnigridsID) -> String?) {
        id = wish.id
        placeID = wish.placeID
        placeName = name(wish.place)
        note = wish.note
        createdAt = wish.createdAt
    }
}

extension LogStore {
    /// The wishlist, oldest first.
    public func wishes() throws -> [Wish] {
        try context.fetch(FetchDescriptor<Wish>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Puts the place on the wishlist, or takes it off. Returns whether it is now on.
    @discardableResult
    public func toggleWish(_ placeID: UnigridsID) throws -> Bool {
        let raw = placeID.rawValue
        let existing = try context.fetch(
            FetchDescriptor<Wish>(predicate: #Predicate { $0.placeID == raw })
        )
        if existing.isEmpty {
            context.insert(Wish(placeID: placeID))
            try save()
            return true
        }
        existing.forEach(context.delete)
        try save()
        return false
    }

    /// A backup's wishes that the log does not already hold, by identifier or by place.
    func mergeWishes(_ items: [WishArchive], into summary: inout MergeSummary) throws {
        let present = try wishes()
        var ids = Set(present.map(\.id))
        var places = Set(present.map(\.placeID))
        for item in items {
            guard !ids.contains(item.id), !places.contains(item.placeID) else {
                summary.alreadyPresent += 1
                continue
            }
            let wish = Wish(placeID: UnigridsID(item.placeID), note: item.note)
            wish.restoreIdentity(item.id, createdAt: item.createdAt)
            context.insert(wish)
            ids.insert(item.id)
            places.insert(item.placeID)
            summary.othersAdded += 1
        }
    }
}
