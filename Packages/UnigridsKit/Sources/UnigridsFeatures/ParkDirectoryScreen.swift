import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The directory: the other way into a park, alongside the map (SPECIFICATION.md §4).
public struct ParkDirectoryScreen: View {
    enum Sort: String, CaseIterable, Identifiable {
        case name
        case state
        case visited

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .name: "Name"
            case .state: "State"
            case .visited: "Visited"
            }
        }
    }

    @Environment(\.referenceStore) private var store
    @Query private var visits: [Visit]

    @State private var query = ""
    @State private var sort: Sort = .name
    @State private var selected: Place?

    public init() {}

    private var index: VisitIndex {
        VisitIndex(visits: visits)
    }

    private var parks: [Place] {
        let base = query.isEmpty
            ? store.nationalParks
            : store.search(query).filter { $0.tier == .nationalPark }
        switch sort {
        case .name:
            return base
        case .state:
            return base.sorted {
                ($0.states.first?.name ?? "", $0.name) < ($1.states.first?.name ?? "", $1.name)
            }
        case .visited:
            return base.sorted {
                let left = index.visitedPlaceIDs.contains($0.id)
                let right = index.visitedPlaceIDs.contains($1.id)
                if left == right {
                    return $0.name < $1.name
                }
                return left && !right
            }
        }
    }

    public var body: some View {
        NavigationStack {
            List(parks) { park in
                NavigationLink {
                    destination(for: park)
                } label: {
                    ParkRow(place: park, status: index.status(for: park.id))
                }
            }
            .listStyle(.inset)
            .searchable(text: $query, prompt: "Search 63 national parks")
            .navigationTitle("Parks")
            .toolbar {
                ToolbarItem {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .overlay {
                if parks.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for park: Place) -> some View {
        if store.guide(for: park.id) != nil {
            ParkGuideScreen(place: park)
        } else {
            PlaceWithoutGuideView(place: park)
        }
    }
}

struct ParkRow: View {
    let place: Place
    let status: VisitStatusBadgeStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: PlaceStyle.symbol(for: place))
                .foregroundStyle(PlaceStyle.tint(for: place))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body.weight(.medium))
                Text(place.statesDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch status {
            case .visited: VisitStatusBadge(status: .visited)
            case .planned: VisitStatusBadge(status: .planned)
            case .none: EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a park without a guide shows. The pilot has four of them; the rest get their
/// guides when the pipeline produces them (docs/mvp-scope.md).
struct PlaceWithoutGuideView: View {
    @Environment(\.referenceStore) private var store
    let place: Place

    @State private var showCheckIn = false
    @State private var showStamp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UnigridTitleBand(
                    name: place.name,
                    designation: place.designation,
                    states: place.statesDescription
                )
                VStack(alignment: .leading, spacing: 14) {
                    ContentUnavailableView {
                        Label("Guide not written yet", systemImage: "book.closed")
                    } description: {
                        Text(
                            "The four pilot parks have full guides. "
                                + "\(place.name) gets one when the data pipeline produces it."
                        )
                    }
                    HStack(spacing: 10) {
                        Button("Check in") { showCheckIn = true }
                            .buttonStyle(.borderedProminent)
                        Button("Stamp") { showStamp = true }
                            .buttonStyle(.bordered)
                    }
                    if let url = place.officialURL {
                        Link("Official NPS page", destination: url)
                            .font(.footnote)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(place.name)
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .sheet(isPresented: $showStamp) { StampSheet(place: place) }
    }
}
