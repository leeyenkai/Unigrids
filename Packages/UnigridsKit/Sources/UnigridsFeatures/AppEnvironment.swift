import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

extension EnvironmentValues {
    /// The bundled reference dataset.
    ///
    /// Defaults to an empty store so a preview or a misconfigured host renders an honest
    /// "no data" state instead of crashing.
    @Entry public var referenceStore: any ReferenceStore = BundledReferenceStore.empty()
}

/// How loading the bundled dataset went, so the app can say so rather than looking broken.
public enum ReferenceLoad {
    case loaded(BundledReferenceStore)
    case failed(BundledReferenceStore, message: String)

    public var store: BundledReferenceStore {
        switch self {
        case let .loaded(store), let .failed(store, _): store
        }
    }

    public var errorMessage: String? {
        switch self {
        case .loaded: nil
        case let .failed(_, message): message
        }
    }

    /// Load the dataset, degrading to an empty store rather than crashing.
    ///
    /// AGENTS.md §3: bundled data failing to load is loud in debug and survivable in
    /// release. A user with a corrupt download gets a screen that explains itself.
    public static func load() -> ReferenceLoad {
        do {
            return try .loaded(BundledReferenceStore.bundled())
        } catch {
            let message = String(describing: error)
            assertionFailure("Reference data failed to load: \(message)")
            return .failed(
                BundledReferenceStore.empty(note: message),
                message: message
            )
        }
    }
}

/// Convenience for views that write to the log.
///
/// Views read with `@Query` and write through `LogStore` (`docs/adr/0004`). The store is
/// a thin wrapper around the context, so building one per use is cheaper than plumbing it
/// through the environment.
extension View {
    @MainActor
    func logStore(_ context: ModelContext) -> LogStore {
        LogStore(context: context)
    }
}

/// Visited and planned status for a set of places, derived from the log.
///
/// The map, the directory and the passport all need the same answer, so it is computed
/// once from a `@Query` result rather than three times from three fetches.
public struct VisitIndex: Sendable {
    public let visitedPlaceIDs: Set<UnigridsID>
    public let plannedPlaceIDs: Set<UnigridsID>

    /// Planned means on the itinerary of a trip that has not finished. A planned trip's
    /// stops are plans, never visits, so they cannot make a place read as visited.
    public init(visits: [Visit], trips: [Trip] = []) {
        visitedPlaceIDs = Set(visits.map(\.place))
        plannedPlaceIDs = Set(
            trips
                .filter { $0.status(on: Date()) != .done }
                .flatMap { ($0.stops ?? []).map(\.place) }
        )
    }

    public func status(for placeID: UnigridsID) -> VisitStatusBadgeStatus {
        if visitedPlaceIDs.contains(placeID) {
            return .visited
        }
        if plannedPlaceIDs.contains(placeID) {
            return .planned
        }
        return .none
    }
}

/// A place's standing in the reader's log, without `UnigridsFeatures` leaking a design type
/// into its own API.
public enum VisitStatusBadgeStatus: Sendable {
    case visited
    case planned
    case none

    var marker: PlaceMarker.Status {
        switch self {
        case .visited: .visited
        case .planned: .planned
        case .none: .none
        }
    }
}
