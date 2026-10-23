import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The trail catalogue (SPECIFICATION.md §8): every national park trail in the NPS public
// layer, measured the same way, filterable by length, climb, effort, loops and features,
// and each one a page with its line, its profile and a way to log the hike.

// MARK: - The list

/// The catalogue's filter bar and rows, as list sections, so it sits inside the
/// directory's list and on a park's own catalogue page alike.
struct TrailCatalogueSections: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query private var hikes: [Hike]

    let trails: [Trail]
    @Binding var filter: TrailFilter
    @Binding var sort: TrailFilter.Sort
    var showsPark = false

    /// A long list is a scrolling chore, not a catalogue: past this, filters do the work.
    private static let shownLimit = 400

    var body: some View {
        let hiked = Set(hikes.map(\.trailID))
        let shown = TrailFilter.sorted(
            trails.filter { filter.includes($0, hiked: hiked.contains($0.id.rawValue)) },
            by: sort
        )
        Section {
            TrailFilterBar(filter: $filter, sort: $sort)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        Section {
            if shown.isEmpty {
                Text(trails.isEmpty
                    ? "No trails are in the NPS public trails data for this park."
                    : "No trails match these filters.")
                    .font(UnigridStyle.prose)
                    .foregroundStyle(style.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(shown.prefix(Self.shownLimit)) { trail in
                NavigationLink {
                    TrailDetailScreen(trail: trail)
                } label: {
                    TrailRow(
                        trail: trail,
                        parkName: showsPark ? store.place(trail.placeID)?.name : nil,
                        hiked: hiked.contains(trail.id.rawValue)
                    )
                }
                .listRowBackground(Color.clear)
            }
            ListNotes {
                if shown.count > Self.shownLimit {
                    Text(
                        "Showing \(Self.shownLimit) of \(shown.count.formatted()). "
                            + "Filter or search to find the rest."
                    )
                }
                Text(
                    "Distances and climbs are for the hike there and back, or once round a loop. "
                        + "Effort is an estimate from them. For planning, not navigation: check "
                        + "conditions with the park before you go."
                )
            }
        } header: {
            SectionHead(
                "Trails",
                detail: "\(shown.count.formatted()) · "
                    + UnigridsFormat.distance(metres: shown.reduce(0) { $0 + $1.lengthMetres })
            )
        }
    }
}

/// Square chips across the top of the catalogue: sort, length, effort, features, loops,
/// and the reader's own log.
struct TrailFilterBar: View {
    @Environment(\.unigrid) private var style
    @Binding var filter: TrailFilter
    @Binding var sort: TrailFilter.Sort

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TrailFilter.Sort.allCases) { Text($0.name).tag($0) }
                    }
                } label: {
                    FilterChip(title: sort.name, symbol: "arrow.up.arrow.down", isOn: false)
                }
                Menu {
                    Picker("Length", selection: $filter.length) {
                        ForEach(TrailFilter.Length.allCases) { Text($0.name).tag($0) }
                    }
                } label: {
                    FilterChip(
                        title: filter.length.name,
                        symbol: "ruler",
                        isOn: filter.length != .any
                    )
                }
                Menu {
                    ForEach(TrailDifficulty.allCases, id: \.self) { band in
                        Toggle(band.name, isOn: membership(band, in: \.difficulties))
                    }
                } label: {
                    FilterChip(
                        title: filter.difficulties.isEmpty ? "Any effort"
                            : "\(filter.difficulties.count) effort bands",
                        symbol: "chart.bar",
                        isOn: !filter.difficulties.isEmpty
                    )
                }
                Menu {
                    ForEach(TrailFeature.allCases) { feature in
                        Toggle(feature.name, isOn: membership(feature, in: \.features))
                    }
                } label: {
                    FilterChip(
                        title: filter.features.isEmpty ? "Features"
                            : TrailFeature.allCases.filter(filter.features.contains)
                            .map(\.name).joined(separator: ", "),
                        symbol: "mountain.2",
                        isOn: !filter.features.isEmpty
                    )
                }
                Button { filter.loopsOnly.toggle() } label: {
                    FilterChip(
                        title: "Loops",
                        symbol: "arrow.triangle.2.circlepath",
                        isOn: filter.loopsOnly
                    )
                }
                .buttonStyle(.plain)
                Button { filter.notYetHiked.toggle() } label: {
                    FilterChip(
                        title: "Not hiked yet",
                        symbol: "figure.hiking",
                        isOn: filter.notYetHiked
                    )
                }
                .buttonStyle(.plain)
                if filter.isNarrowed {
                    Button("Clear") {
                        let query = filter.query
                        filter = TrailFilter(query: query)
                    }
                    .font(UnigridStyle.action)
                    .buttonStyle(.plain)
                    .foregroundStyle(style.accent)
                }
            }
            .padding(.horizontal, UnigridStyle.pageMargin)
        }
        .scrollIndicators(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func membership<Value: Hashable>(
        _ value: Value,
        in path: WritableKeyPath<TrailFilter, Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { filter[keyPath: path].contains(value) },
            set: { isOn in
                if isOn {
                    filter[keyPath: path].insert(value)
                } else {
                    filter[keyPath: path].remove(value)
                }
            }
        )
    }
}

/// One square filter chip: ink when on, ruled when off.
struct FilterChip: View {
    @Environment(\.unigrid) private var style
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(BrochureLabelStyle())
            .font(UnigridStyle.rowDetail)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? style.page : style.ink)
            .background(isOn ? style.ink : Color.clear)
            .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1) }
            .contentShape(Rectangle())
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One park's catalogue, as a page of its own.
struct TrailCatalogueScreen: View {
    @Environment(\.referenceStore) private var store
    let place: Place

    @State private var filter = TrailFilter()
    @AppStorage("trails.sort") private var sort = TrailFilter.Sort.length

    var body: some View {
        let trails = store.trails(in: place.id)
        List {
            Section {
                BandHeader(
                    "Trails",
                    kicker: "\(place.name) · \(trails.count) trails · "
                        + UnigridsFormat.distance(metres: trails.reduce(0) { $0 + $1.lengthMetres })
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            TrailCatalogueSections(trails: trails, filter: $filter, sort: $sort)
        }
        .listStyle(.plain)
        .paperPage()
        .searchable(text: $filter.query, prompt: "Search \(place.name)'s trails")
        .navigationTitle("Trails")
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - A trail's page

/// A trail's page: its line on the map, its figures and profile, the sights along it,
/// what the park records about it, and the way to log it.
struct TrailDetailScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let trail: Trail

    @State private var showExplorer = false
    @State private var showParkMap = false

    private var place: Place? {
        store.place(trail.placeID)
    }

    private var hasPack: Bool {
        OfflinePackCatalogue.bundled.pack(for: trail.placeID) != nil
    }

    private var sights: [PointOfInterest] {
        trail.sightIDs.compactMap { id in store.sights(in: trail.placeID).first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                UnigridTitleBand(
                    name: trail.name,
                    designation: trail.routeType == .loop ? "Loop trail" : "Trail",
                    states: place?.name ?? ""
                )
                VStack(spacing: UnigridStyle.gutter) {
                    UnigridPanel(title: "The trail") {
                        VStack(alignment: .leading, spacing: 14) {
                            TrailFigures(trail: trail)
                            if let effort = trail.estimatedDifficulty {
                                UnigridDataRow(label: "Effort, estimated", value: effort.name)
                            }
                            if let place {
                                TrailMap(trail: trail, place: place, sights: sights)
                                    .frame(height: 280)
                                    .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                                WrappingRow {
                                    Button { showExplorer = true } label: {
                                        Label("Explore in 3D", symbol: .explore3D)
                                    }
                                    if hasPack {
                                        Button { showParkMap = true } label: {
                                            Label("On the park map", symbol: .parkMap)
                                        }
                                    }
                                }
                                .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
                            }
                        }
                    }
                    if trail.profile.count >= 2 {
                        UnigridPanel(title: "Elevation") {
                            VStack(alignment: .leading, spacing: 10) {
                                TrailProfileChart(trail: trail, height: 180)
                                if let range = UnigridsFormat.elevationRange(
                                    lowest: trail.lowPointMetres, highest: trail.highPointMetres
                                ) {
                                    UnigridDataRow(label: "Range", value: range)
                                }
                                if let loss = trail.lossMetres {
                                    UnigridDataRow(
                                        label: "Descent",
                                        value: UnigridsFormat.elevation(loss)
                                    )
                                }
                            }
                        }
                    }
                    if !sights.isEmpty {
                        UnigridPanel(title: "Along the way") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(sights) { sight in
                                    HStack(spacing: 10) {
                                        SightNumber(number: sight.rank)
                                        Text(sight.name)
                                            .font(UnigridStyle.itemTitle)
                                            .foregroundStyle(style.ink)
                                    }
                                }
                            }
                        }
                    }
                    TrailNotesPanel(trail: trail)
                    UnigridPanel(title: "Your hike") {
                        VStack(alignment: .leading, spacing: 8) {
                            TrailActions(trail: trail)
                            if let start = trail.start {
                                Button {
                                    openInMaps(start, name: "\(trail.name) start")
                                } label: {
                                    Label(
                                        "Directions to the start",
                                        symbol: .directions
                                    )
                                }
                                .buttonStyle(BrochureButtonStyle(.secondary))
                            }
                        }
                    }
                    GuideCreditsPanel(
                        credits: [Self.credit(for: trail)],
                        sources: [],
                        photos: []
                    )
                }
                .padding(UnigridStyle.pageMargin)
            }
        }
        .background(style.page)
        .navigationTitle(trail.name)
        .toolbarTitleDisplayMode(.inline)
        .modifier(TrailExplorerPresenter(isPresented: $showExplorer, trail: trail, place: place))
        .modifier(TrailParkMapPresenter(isPresented: $showParkMap, trail: trail, place: place))
    }
}

extension TrailDetailScreen {
    /// The trail's own source first — the NPS's public trails data, or OpenStreetMap under
    /// the ODbL — then how Unigrids measured it.
    static func credit(for trail: Trail) -> String {
        let line = trail.isFromOpenStreetMap
            ? "Trail line © OpenStreetMap contributors, available under the Open Database "
            + "Licence (ODbL). "
            : "Trail line from the National Park Service's public trails data. "
        return line
            + "Length, climb and profile measured by Unigrids from USGS 3DEP elevation at a "
            + "station every 30 m; effort estimated from them by Shenandoah National Park's "
            + "published rating. For planning, not navigation."
    }
}

/// What the park's data says about a trail: who may use it, when, and on what surface.
struct TrailNotesPanel: View {
    let trail: Trail

    var body: some View {
        if trail.uses != nil || trail.seasonalNotes != nil || trail.bikesAllowed != nil {
            UnigridPanel(title: "From the park") {
                VStack(alignment: .leading, spacing: 8) {
                    if let uses = trail.uses {
                        UnigridDataRow(label: "Open to", value: uses)
                    }
                    if trail.bikesAllowed == true {
                        UnigridDataRow(label: "Bikes", value: "Allowed")
                    }
                    if let notes = trail.seasonalNotes {
                        GuideNote(label: "Seasons", text: notes)
                    }
                }
            }
        }
    }
}

/// A trail on a map: its line, its start, the sights it passes.
struct TrailMap: View {
    @Environment(\.unigrid) private var style
    let trail: Trail
    let place: Place
    let sights: [PointOfInterest]

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        content.graphicTypeSize()
    }

    private var content: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(Array(trail.paths.enumerated()), id: \.offset) { _, path in
                MapPolyline(coordinates: path.map(\.clCoordinate))
                    .stroke(
                        style.trail,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            if let start = trail.start {
                Annotation("Start", coordinate: start.clCoordinate) {
                    Circle()
                        .fill(style.panel)
                        .overlay { Circle().strokeBorder(style.ink, lineWidth: 2.5) }
                        .frame(width: 12, height: 12)
                }
            }
            ForEach(sights) { sight in
                Annotation(sight.name, coordinate: sight.location.clCoordinate) {
                    SightNumber(number: sight.rank)
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            emphasis: .muted,
            pointsOfInterest: .excludingAll
        ))
        .onAppear {
            if let extent = trail.extent {
                position = .rect(MKMapRect(box: extent.expanded(by: 0.2)))
            }
        }
    }
}

/// The explorer, opened on a trail.
private struct TrailExplorerPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let trail: Trail
    let place: Place?

    func body(content: Content) -> some View {
        if let place {
            content.explorer(isPresented: $isPresented, place: place, focus: .trail(trail.id))
        } else {
            content
        }
    }
}

private struct TrailParkMapPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let trail: Trail
    let place: Place?

    func body(content: Content) -> some View {
        if let place {
            content.parkMap(isPresented: $isPresented, place: place, focusTrail: trail.id)
        } else {
            content
        }
    }
}

/// Hand a coordinate to Apple Maps for directions.
@MainActor
func openInMaps(_ coordinate: Coordinate, name: String) {
    let item = MKMapItem(
        location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
        address: nil
    )
    item.name = name
    item.openInMaps()
}
