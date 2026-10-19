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

    private let loadErrorMessage: String?

    public init(loadErrorMessage: String? = nil) {
        self.loadErrorMessage = loadErrorMessage
    }

    public var body: some View {
        TabView {
            Tab("Map", systemImage: "map") {
                MapScreen()
            }
            Tab("Parks", systemImage: "square.grid.3x3") {
                ParkDirectoryScreen()
            }
            Tab("Trips", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                TripsScreen()
            }
            Tab("Passport", systemImage: "book.closed") {
                PassportScreen()
            }
            Tab("Stats", systemImage: "chart.bar") {
                StatsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .top) {
            if let loadErrorMessage {
                DataUnavailableBanner(message: loadErrorMessage)
            }
        }
        .onboarding(isPresented: showOnboarding) {
            OnboardingView { onboardingSeen = true }
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !onboardingSeen }, set: {
            if !$0 {
                onboardingSeen = true
            }
        })
    }
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
