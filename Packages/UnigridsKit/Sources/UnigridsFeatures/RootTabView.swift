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

    private let loadErrorMessage: String?

    public init(loadErrorMessage: String? = nil) {
        self.loadErrorMessage = loadErrorMessage
    }

    public var body: some View {
        TabView {
            Tab("Map", systemImage: "map") {
                MapScreen()
            }
            Tab("Parks", systemImage: "tree") {
                ParkDirectoryScreen()
            }
            Tab("Trips", systemImage: "suitcase") {
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
