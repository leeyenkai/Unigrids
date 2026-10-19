import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The directory: the other way into a park, alongside the map (SPECIFICATION.md §4) —
/// set as a brochure's index, with the sixty-three national parks as a grid of squares
/// that fills in as the reader visits them.
public struct ParkDirectoryScreen: View {
    enum Scope: String, CaseIterable, Identifiable {
        case nationalParks
        case everything

        var id: String {
            rawValue
        }

        var name: String {
            switch self {
            case .nationalParks: "National parks"
            case .everything: "Every place"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case name
        case state
        case visited

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .name: "A to Z"
            case .state: "By state"
            case .visited: "Visited first"
            }
        }
    }

    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query private var visits: [Visit]
    @Query private var trips: [Trip]

    @State private var query = ""
    @AppStorage("parks.scope") private var scope = Scope.nationalParks
    @AppStorage("parks.sort") private var sort = Sort.name

    public init() {}

    private var index: VisitIndex {
        VisitIndex(visits: visits, trips: trips)
    }

    private var places: [Place] {
        if query.isEmpty {
            scope == .nationalParks ? store.nationalParks : store.places
                .sorted { $0.name < $1.name }
        } else {
            store.search(query, limit: 200)
                .filter { scope == .everything || $0.tier == .nationalPark }
        }
    }

    private var sections: [(String, [Place])] {
        let index = index
        switch sort {
        case .name:
            let grouped = Dictionary(grouping: places) { String($0.name.prefix(1)).uppercased() }
            return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
        case .state:
            let grouped = Dictionary(grouping: places) { $0.states.first?.name ?? "Other" }
            return grouped.keys.sorted().map { key in
                (key, (grouped[key] ?? []).sorted { $0.name < $1.name })
            }
        case .visited:
            let visited = places.filter { index.visitedPlaceIDs.contains($0.id) }
            let planned = places.filter {
                index.plannedPlaceIDs.contains($0.id) && !index.visitedPlaceIDs.contains($0.id)
            }
            let rest = places.filter {
                !index.visitedPlaceIDs.contains($0.id) && !index.plannedPlaceIDs.contains($0.id)
            }
            return [("Visited", visited), ("Planned", planned), ("Not yet", rest)]
                .filter { !$0.1.isEmpty }
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    DirectoryHeader(
                        parks: store.nationalParks,
                        index: index,
                        otherCount: store.places.count - store.nationalParks.count
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Picker("Show", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(sections, id: \.0) { title, places in
                    Section {
                        ForEach(places) { place in
                            NavigationLink(value: place.id) {
                                PlaceRow(place: place, status: index.status(for: place.id))
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        SectionHead(title, detail: "\(places.count)")
                            .padding(.top, 6)
                    }
                }
            }
            .listStyle(.plain)
            .paperPage()
            .searchable(
                text: $query,
                prompt: scope == .nationalParks
                    ? "Search 63 national parks" : "Search every place"
            )
            .navigationTitle("Parks")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .overlay {
                if places.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationDestination(for: UnigridsID.self) { id in
                PlaceDestination(placeID: id)
            }
        }
    }
}

/// The directory's head: the band, and the sixty-three squares.
struct DirectoryHeader: View {
    @Environment(\.unigrid) private var style
    let parks: [Place]
    let index: VisitIndex
    let otherCount: Int

    var body: some View {
        let visited = parks.count { index.visitedPlaceIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Parks", kicker: "63 national parks · \(otherCount) more places")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(visited)")
                        .font(UnigridStyle.figure)
                        .foregroundStyle(style.ink)
                        .monospacedDigit()
                    Text("of \(parks.count) national parks visited")
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
                ParkGrid(parks: parks, index: index)
            }
            .padding(UnigridStyle.pageMargin)
        }
    }
}

/// The national parks as a grid of squares, one each, filled when visited — the app's
/// name made literal, and the completion figure drawn rather than charted.
struct ParkGrid: View {
    @Environment(\.unigrid) private var style
    let parks: [Place]
    let index: VisitIndex
    var side: CGFloat = 22

    var body: some View {
        let tint = Color(AgencyInk.nationalPark.value(style.scheme))
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: side, maximum: side), spacing: 4)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(parks) { park in
                let status = index.status(for: park.id)
                Rectangle()
                    .fill(status == .visited ? tint : Color.clear)
                    .overlay {
                        Rectangle().strokeBorder(
                            tint,
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                dash: status == .planned ? [3, 2] : []
                            )
                        )
                    }
                    .frame(width: side, height: side)
                    .help(park.name)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(parks.count { index.visitedPlaceIDs.contains($0.id) }) of \(parks.count) "
                + "national parks visited"
        )
    }
}

/// A row in the index: the place's marker, its name, its designation and states, and
/// whether the reader has been.
struct PlaceRow: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let status: VisitStatusBadgeStatus

    var body: some View {
        HStack(spacing: 12) {
            PlaceMarker(tier: place.tier, tint: style.agencyTint(for: place), status: status.marker)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Text("\(place.designation) · \(place.statesDescription)")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            switch status {
            case .visited:
                Kicker("Visited")
            case .planned:
                Kicker("Planned")
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
