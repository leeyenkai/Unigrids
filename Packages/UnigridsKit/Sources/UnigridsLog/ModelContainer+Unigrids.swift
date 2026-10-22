import Foundation
import SQLite3
import SwiftData

/// The user-data schema, in one place so the app, the tests and any future widget or
/// Watch target cannot drift apart.
public enum UnigridsSchema {
    public static let models: [any PersistentModel.Type] = [
        Trip.self,
        TripStop.self,
        Visit.self,
        CheckIn.self,
        Hike.self,
        Stamp.self,
        Reminder.self,
        WeatherSnapshot.self,
    ]

    public static var schema: Schema {
        Schema(models)
    }
}

public enum UnigridsModelContainer {
    /// Where the log lives: `Application Support/Unigrids/Unigrids.store`.
    ///
    /// Named rather than left to SwiftData's default, `Application Support/default.store`.
    /// On the Mac, while the app is not sandboxed, that default is one file in the user's
    /// own Library shared by every unsandboxed SwiftData app — a log that any of them could
    /// open, migrate or delete.
    public static var storeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Unigrids", directoryHint: .isDirectory)
            .appending(path: "Unigrids.store", directoryHint: .notDirectory)
    }

    /// The app's container, synced through the user's own private CloudKit database.
    ///
    /// `.automatic` uses the CloudKit container the app's entitlements name, and stores
    /// locally when there is none — the app works without iCloud, it just does not sync.
    /// A log left at SwiftData's default location by an earlier build is moved here first.
    public static func app(at url: URL = storeURL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try StoreMigration.moveDefaultStoreIfNeeded(to: url)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema, url: url, cloudKitDatabase: .automatic
            )
        )
    }

    /// A container on a file of the caller's choosing, without sync: for tests that need a
    /// store to outlive its container.
    public static func local(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        )
    }

    /// A container with no sync and no file, for tests and previews.
    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }

    private static var schema: Schema {
        UnigridsSchema.schema
    }
}

/// Moving a log out of SwiftData's default location, once.
public enum StoreMigration {
    /// SwiftData's default store, where builds before the log had a name of its own kept it.
    public static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// The tables that make a store this app's: a store at the default location without
    /// them belongs to some other app and is left exactly where it is.
    static let signatureTables: Set<String> = ["ZVISIT", "ZSTAMP", "ZTRIPSTOP"]

    /// Move the default store and its write-ahead files to `destination`, if there is no
    /// store there yet and the default one is verifiably this app's.
    ///
    /// Copied, checked, then removed, rather than moved: an interruption part way leaves
    /// the original whole, and the copy is only trusted once it reads as this app's log.
    public static func moveDefaultStoreIfNeeded(
        to destination: URL,
        from source: URL = defaultStoreURL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.fileExists(atPath: source.path),
              holdsUnigridsLog(source)
        else { return }
        let suffixes = ["", "-wal", "-shm"].filter {
            fileManager.fileExists(atPath: source.path + $0)
        }
        do {
            for suffix in suffixes {
                try fileManager.copyItem(
                    atPath: source.path + suffix, toPath: destination.path + suffix
                )
            }
            guard holdsUnigridsLog(destination) else {
                throw CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [NSFilePathErrorKey: destination.path]
                )
            }
        } catch {
            for suffix in suffixes {
                try? fileManager.removeItem(atPath: destination.path + suffix)
            }
            throw error
        }
        for suffix in suffixes {
            try? fileManager.removeItem(atPath: source.path + suffix)
        }
    }

    /// Whether the SQLite file at `url` has this app's tables, read without changing it.
    ///
    /// Read-only first, which sees anything still in the write-ahead log. A WAL database
    /// whose shared-memory file is gone cannot be opened that way — a read-only connection
    /// may not create one — so failing that it is read as immutable, which is right for a
    /// store nothing has open, as one is before the app opens it.
    static func holdsUnigridsLog(_ url: URL) -> Bool {
        ["mode=ro", "immutable=1"].contains { option in
            tables(at: "\(url.absoluteString)?\(option)").map(signatureTables.isSubset) ?? false
        }
    }

    private static func tables(at uri: String) -> Set<String>? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT name FROM sqlite_master WHERE type = 'table'"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        var tables: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                tables.insert(String(cString: name))
            }
        }
        return tables
    }
}
