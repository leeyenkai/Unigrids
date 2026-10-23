import Foundation
import Observation
import SwiftData
import SwiftUI
import UnigridsDesign
import UnigridsLog
#if os(iOS)
    import UIKit
#endif

/// Whether files protected until first unlock can be read yet.
///
/// iOS can launch the app in the background — to deliver a region event, say — before the
/// phone has been unlocked since it restarted. Until then the log's store and the user
/// defaults read as missing, and anything that writes as if they were empty overwrites
/// what is really there.
@MainActor
enum ProtectedData {
    static var isAvailable: Bool {
        #if os(iOS)
            UIApplication.shared.isProtectedDataAvailable
        #else
            true
        #endif
    }

    /// Returns once protected data can be read, at once if it already can.
    static func available() async {
        #if os(iOS)
            // Listening before looking: an unlock between the look and the listen would
            // otherwise be missed, and the wait would last until the next one.
            var unlocks = NotificationCenter.default.notifications(
                named: UIApplication.protectedDataDidBecomeAvailableNotification
            ).makeAsyncIterator()
            guard !isAvailable else { return }
            _ = await unlocks.next()
        #endif
    }
}

/// Opens the user's log, and says honestly when it cannot.
///
/// The app once fell back to an in-memory store when the real one would not open, and
/// carried on as if nothing were wrong: the log looked empty, and everything logged that
/// session vanished at quit. Now the app waits for the phone to be unlocked if that is
/// the reason, retries once, and otherwise stops with the error and a Retry — the data is
/// still on disk, and nothing is written anywhere it would be lost.
@MainActor
@Observable
public final class StoreLoader {
    public enum State {
        case opening
        case waitingForUnlock
        case ready(ModelContainer)
        case failed(String)
    }

    public private(set) var state: State = .opening
    private let open: @MainActor () throws -> ModelContainer
    private var loading = false

    /// The app's log; with `sampleData`, a screenshot run's throwaway sample instead.
    public init(sampleData: Bool = false) {
        if sampleData {
            open = {
                let container = try UnigridsModelContainer.inMemory()
                DebugSampleData.seed(container)
                return container
            }
        } else {
            open = { try UnigridsModelContainer.app() }
        }
    }

    init(open: @escaping @MainActor () throws -> ModelContainer) {
        self.open = open
    }

    public var container: ModelContainer? {
        if case let .ready(container) = state {
            return container
        }
        return nil
    }

    /// Open the store, once; later calls while it is open do nothing.
    public func load() async {
        guard container == nil, !loading else { return }
        loading = true
        defer { loading = false }
        if !ProtectedData.isAvailable {
            state = .waitingForUnlock
            await ProtectedData.available()
        }
        state = .opening
        do {
            state = try .ready(open())
        } catch {
            // One retry: a store busy with a migration or a file briefly locked by the
            // system clears itself in a moment.
            try? await Task.sleep(for: .seconds(1))
            do {
                state = try .ready(open())
            } catch {
                state = .failed(String(describing: error))
            }
        }
    }

    /// Try again after a failure.
    public func retry() async {
        if case .failed = state {
            state = .opening
        }
        await load()
    }
}

/// Shows `content` with the open log, or what is keeping it shut.
public struct LogGate<Content: View>: View {
    private let loader: StoreLoader
    private let content: (ModelContainer) -> Content

    public init(loader: StoreLoader, @ViewBuilder content: @escaping (ModelContainer) -> Content) {
        self.loader = loader
        self.content = content
    }

    public var body: some View {
        Group {
            switch loader.state {
            case let .ready(container):
                content(container)
            case .opening:
                LogStatusView(
                    title: "Opening your log",
                    message: nil,
                    action: nil
                )
            case .waitingForUnlock:
                LogStatusView(
                    title: "Unlock to open your log",
                    message: "Your trips, visits and stamps are protected until this device "
                        + "has been unlocked since it restarted.",
                    action: nil
                )
            case let .failed(error):
                LogStatusView(
                    title: "Your log could not be opened",
                    message: "Nothing has been lost: your data is still on this device, and "
                        + "Unigrids has not written anything in its place. Try again, or "
                        + "restart the app.\n\n\(error)",
                    action: { Task { await loader.retry() } }
                )
            }
        }
        .task { await loader.load() }
    }
}

private struct LogStatusView: View {
    @Environment(\.unigrid) private var style
    let title: String
    let message: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Unigrids", kicker: title)
            VStack(alignment: .leading, spacing: 16) {
                if let message {
                    Text(message)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                }
                if let action {
                    Button("Try again", action: action)
                        .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                }
            }
            .padding(UnigridStyle.pageMargin)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.page)
    }
}
