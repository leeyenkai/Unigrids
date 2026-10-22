import Foundation
import Observation
import UnigridsCore
import UnigridsReference

/// The road and rail network, decoded once, off the main actor, the first time anything
/// asks — the map's layers, or a page's "by train" line — and shared after that.
@MainActor
@Observable
public final class TransportStore {
    public private(set) var network = TransportNetwork.empty
    private var loading: Task<Void, Never>?

    public init() {}

    /// Load the network if it is not loaded yet. Safe to call from every view that wants it.
    public func load(from store: any ReferenceStore) async {
        if !network.isEmpty {
            return
        }
        if let loading {
            await loading.value
            return
        }
        let task = Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                (try? store.transportNetwork()) ?? .empty
            }.value
            network = decoded
        }
        loading = task
        await task.value
        loading = nil
    }
}
