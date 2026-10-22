import SwiftData
import SwiftUI
import UnigridsCore
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

    /// The user's log, opened when the first window appears — never before the device
    /// can read it, and never replaced by a store that would vanish at quit.
    @State private var log = StoreLoader(sampleData: DebugSampleData.isRequested)

    init() {
        AppServices.startRoutingNotifications()
        #if os(iOS)
            // As early as possible: iOS relaunches the app in the background to deliver an
            // arrival, and the monitor has to be listening by the time it does.
            VisitDetection.resume(store: reference.store)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LogGate(loader: log) { container in
                RootTabView(loadErrorMessage: reference.errorMessage)
                    .environment(\.referenceStore, reference.store)
                    .modelContainer(container)
            }
            .unigridsAppearance()
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif

        #if os(macOS)
            // A guide or leaflet in a window of its own, beside the map.
            WindowGroup("Place", for: UnigridsID.self) { $placeID in
                LogGate(loader: log) { container in
                    PlaceWindow(placeID: placeID)
                        .environment(\.referenceStore, reference.store)
                        .modelContainer(container)
                        .unigridsServices()
                }
                .unigridsAppearance()
            }
            .defaultSize(width: 1180, height: 860)
        #endif

        #if os(macOS)
            Settings {
                // The second root. It needs the appearance for the same reason the window
                // does, and the container because `SettingsScreen` queries visits and
                // stamps — without one it reported zero of each on the Mac.
                LogGate(loader: log) { container in
                    NavigationStack {
                        SettingsScreen()
                    }
                    .environment(\.referenceStore, reference.store)
                    .modelContainer(container)
                    .unigridsServices()
                }
                .unigridsAppearance()
                .frame(width: 560, height: 680)
            }
        #endif
    }
}
