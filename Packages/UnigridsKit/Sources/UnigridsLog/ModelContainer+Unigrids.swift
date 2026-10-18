import Foundation
import SwiftData

/// The user-data schema, in one place so the app, the tests and any future widget or
/// Watch target cannot drift apart.
public enum UnigridsSchema {
    public static let models: [any PersistentModel.Type] = [
        Trip.self,
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
    /// The app's container, synced through the user's own private CloudKit database.
    ///
    /// `.automatic` uses the CloudKit container the app's entitlements name, and falls
    /// back to local-only storage when the user is not signed into iCloud — which is the
    /// behaviour we want: the app works without iCloud, it just does not sync.
    public static func app() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
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
