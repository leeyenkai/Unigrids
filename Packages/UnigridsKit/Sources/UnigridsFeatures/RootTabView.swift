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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var reminders: [Reminder]
    @State private var tab = DebugLaunch.tab.flatMap(AppTab.init(rawValue:)) ?? .map
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    private let loadErrorMessage: String?

    public init(loadErrorMessage: String? = nil) {
        self.loadErrorMessage = loadErrorMessage
    }

    public var body: some View {
        TabView(selection: $tab) {
            Tab("Map", systemImage: UnigridsSymbol.map.systemName, value: AppTab.map) {
                MapScreen()
            }
            Tab("Parks", systemImage: UnigridsSymbol.parks.systemName, value: AppTab.parks) {
                ParkDirectoryScreen()
            }
            Tab("Trips", systemImage: UnigridsSymbol.trips.systemName, value: AppTab.trips) {
                TripsScreen()
            }
            // Arrivals waiting for an answer, so a suggestion is seen from any tab.
            .badge(arrivals)
            Tab(
                "Passport",
                systemImage: UnigridsSymbol.passport.systemName,
                value: AppTab.passport
            ) {
                PassportScreen()
            }
            Tab("Stats", systemImage: UnigridsSymbol.stats.systemName, value: AppTab.stats) {
                StatsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .undoHost()
        .unigridsServices()
        .task(id: upcomingPlaceIDs) {
            await AppServices.brochures.prefetch(placeIDs: upcomingPlaceIDs, store: store)
        }
        .onChange(of: visitCount, initial: true) {
            WeatherBackfill.schedule(context: context, store: store)
        }
        .task(id: reminders.count) {
            // The log is the truth: schedule what synced in, drop what was deleted.
            await ReminderScheduler.reconcile(reminders)
        }
        .onChange(of: AppServices.router.pending, initial: true) { _, route in
            showTab(for: route)
        }
        .onChange(of: scenePhase) { showTab(for: AppServices.router.pending) }
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
        #if os(macOS)
        .onAppear {
            if DebugLaunch.opensSettings {
                openSettings()
            }
        }
        #endif
        .onboarding(isPresented: showOnboarding) {
            OnboardingView { onboardingSeen = true }
        }
    }

    /// Bring forward the tab a notification's route belongs to; the tab's own screen
    /// takes the route from there. Only the window the reader is looking at moves.
    private func showTab(for route: AppRoute?) {
        guard let route, scenePhase == .active else { return }
        switch route {
        case .arrival, .trip: tab = .trips
        case .place: tab = .map
        }
    }

    private var arrivals: Int {
        DetectedVisits.unanswered(AppServices.detected.pending, visits: visits, store: store).count
    }

    private var visitCount: Int {
        visits.count
    }

    /// The parks on trips still to come, whose brochures are kept for offline (§6).
    private var upcomingPlaceIDs: [UnigridsID] {
        trips
            .filter { $0.status(on: Date()) != .done }
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
    @Environment(\.unigrid) private var style
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reference data unavailable", symbol: .warningFilled)
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
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
