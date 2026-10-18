import SwiftData
import SwiftUI
import UnigridsFeatures
import UnigridsLog

/// The whole app target: an entry point, assets and Info.plist settings.
///
/// Everything else lives in `Packages/UnigridsKit` so it compiles and tests in seconds
/// without Xcode's build system (`docs/adr/0003`).
@main
struct UnigridsApp: App {
    /// The bundled dataset, or an empty store plus a message if it could not be read.
    private let reference = ReferenceLoad.load()

    /// The user's log. Falls back to an in-memory store so a container failure leaves a
    /// usable app with an honest warning rather than a launch crash.
    private let userData: Result<ModelContainer, any Error>

    init() {
        userData = Result { try UnigridsModelContainer.app() }
            .flatMapError { appError in
                Result { try UnigridsModelContainer.inMemory() }
                    .mapError { _ in appError }
            }
    }

    var body: some Scene {
        WindowGroup {
            switch userData {
            case let .success(container):
                RootTabView(loadErrorMessage: reference.errorMessage)
                    .environment(\.referenceStore, reference.store)
                    .modelContainer(container)
                    .unigridsAppearance()
            case let .failure(error):
                StoreUnavailableView(message: String(describing: error))
                    .unigridsAppearance()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif

        #if os(macOS)
            Settings {
                // The second root. It needs the appearance for the same reason the window
                // does, and the container because `SettingsScreen` queries visits and
                // stamps — without one it reported zero of each on the Mac.
                switch userData {
                case let .success(container):
                    SettingsScreen()
                        .environment(\.referenceStore, reference.store)
                        .modelContainer(container)
                        .unigridsAppearance()
                        .frame(width: 520, height: 620)
                case let .failure(error):
                    StoreUnavailableView(message: String(describing: error))
                        .unigridsAppearance()
                        .frame(width: 520, height: 620)
                }
            }
        #endif
    }
}

/// The last resort: neither the CloudKit-backed store nor an in-memory one would open.
private struct StoreUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Your log could not be opened", systemImage: "exclamationmark.icloud")
        } description: {
            VStack(spacing: 12) {
                Text(
                    "Unigrids could not open its data store, so nothing can be logged "
                        + "right now. Restarting the app usually clears this."
                )
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
