import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The five tabs that share one place database and one visit log, so a check-in made
/// anywhere shows up everywhere (SPECIFICATION.md §4).
///
/// Map and Parks are the two ways into a park; Trips, Passport and Stats all read the
/// same log.
public struct RootTabView: View {
    @Environment(\.referenceStore) private var store
    @AppStorage(OnboardingDefaults.seen) private var onboardingSeen = false
    @Query private var trips: [Trip]
    @Query private var visits: [Visit]
    @Environment(\.modelContext) private var context
    @State private var tab = DebugLaunch.tab.flatMap(AppTab.init(rawValue:)) ?? .map

    private let loadErrorMessage: String?

    public init(loadErrorMessage: String? = nil) {
        self.loadErrorMessage = loadErrorMessage
    }

    public var body: some View {
        TabView(selection: $tab) {
            Tab("Map", systemImage: "map", value: AppTab.map) {
                MapScreen()
            }
            Tab("Parks", systemImage: "square.grid.3x3", value: AppTab.parks) {
                ParkDirectoryScreen()
            }
            Tab(
                "Trips",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                value: AppTab.trips
            ) {
                TripsScreen()
            }
            Tab("Passport", systemImage: "book.closed", value: AppTab.passport) {
                PassportScreen()
            }
            Tab("Stats", systemImage: "chart.bar", value: AppTab.stats) {
                StatsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .unigridsServices()
        .overlay(alignment: .bottom) {
            UndoToast()
                .animation(.easeInOut(duration: 0.25), value: AppServices.undo.current?.id)
        }
        .task(id: upcomingPlaceIDs) {
            await AppServices.brochures.prefetch(placeIDs: upcomingPlaceIDs, store: store)
        }
        .task(id: visitCount) {
            await WeatherBackfill.run(context: context, store: store)
        }
        .task {
            // Decode the trail catalogue off the main actor once the map is up, so the first
            // guide or the Stats tab finds it ready.
            let store = store
            await Task.detached(priority: .background) { _ = store.allTrails.count }.value
        }
        .overlay(alignment: .top) {
            if let loadErrorMessage {
                DataUnavailableBanner(message: loadErrorMessage)
            }
        }
        .onboarding(isPresented: showOnboarding) {
            OnboardingView { onboardingSeen = true }
        }
    }

    private var visitCount: Int {
        visits.count
    }

    /// The parks on trips still to come, whose brochures are kept for offline (§6).
    private var upcomingPlaceIDs: [UnigridsID] {
        trips
            .filter { $0.status != .done }
            .flatMap(\.orderedStops)
            .map(\.place)
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !onboardingSeen }, set: {
            if !$0 {
                onboardingSeen = true
            }
        })
    }
}

/// The five tabs (SPECIFICATION.md §4).
enum AppTab: String, Hashable {
    case map
    case parks
    case trips
    case passport
    case stats
}

/// Shown when the bundled dataset could not be read, which otherwise looks like an app
/// with no parks in it.
struct DataUnavailableBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reference data unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NativeMetrics.chipRadius))
        .padding(.horizontal, 16)
    }
}

extension View {
    /// The welcome, full screen on iPhone and iPad and as a fixed-size sheet on the Mac,
    /// where a full-screen cover does not exist.
    fileprivate func onboarding(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        #if os(iOS)
            fullScreenCover(isPresented: isPresented, content: content)
        #else
            sheet(isPresented: isPresented) {
                content().frame(width: 620, height: 640)
            }
        #endif
    }
}
