import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The map the app opens on (SPECIFICATION.md §5): every covered place across the US,
/// national parks outlined from the start and everything else outlined as the camera
/// comes in. Tapping a pin — or anywhere inside an outline — opens that place's overview.
public struct MapScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query private var visits: [Visit]
    @Query private var trips: [Trip]

    @State private var path = NavigationPath()
    @State private var selection: UnigridsID?
    @State private var camera: AtlasCameraRequest?
    @State private var filter = MapFilter.everything
    @State private var query = ""
    @State private var showFilters = false
    @AppStorage("map.basemap") private var basemap = AtlasBasemap.standard

    public init() {}

    private var index: VisitIndex {
        VisitIndex(visits: visits, trips: trips)
    }

    private var atlasPlaces: [AtlasPlace] {
        let index = index
        return store.places.compactMap { place in
            let status = index.status(for: place.id)
            guard filter.includes(place, isVisited: status == .visited) else { return nil }
            return AtlasPlace(place: place, status: status)
        }
    }

    private var boundaries: [UnigridsID: PlaceBoundary] {
        store.boundaries
    }

    private var selectedPlace: Place? {
        selection.flatMap(store.place)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            AtlasMapView(
                places: atlasPlaces,
                boundaries: boundaries,
                selection: selection,
                camera: camera,
                basemap: basemap,
                ink: AtlasInk(scheme: style.scheme, palette: style.palette),
                onSelect: { selection = $0 },
                onRegionChange: { _ in }
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .overlay(alignment: .bottomLeading) {
                MapLegend(filter: filter, counts: tierCounts) { showFilters = true }
                    .padding(12)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                RegionShortcutBar { box in
                    camera = AtlasCameraRequest(box: box)
                }
            }
            .navigationTitle("Map")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Parks, monuments, sights")
            .searchSuggestions {
                MapSearchSuggestions(query: query) { result in
                    select(result)
                }
            }
            .toolbar { toolbar }
            .inspector(isPresented: inspectorBinding) {
                if let place = selectedPlace {
                    PlaceOverviewPanel(place: place, onOpen: open, onClose: { selection = nil })
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
                        .presentationDetents([.height(360), .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .height(360)))
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showFilters) {
                MapFilterSheet(filter: $filter, counts: tierCounts)
            }
            .navigationDestination(for: UnigridsID.self) { id in
                PlaceDestination(placeID: id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                showFilters = true
            } label: {
                Label(
                    "Filter",
                    systemImage: filter.isNarrowed
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
        ToolbarItem {
            Menu {
                Picker("Base map", selection: $basemap) {
                    ForEach(AtlasBasemap.allCases) { option in
                        Label(option.name, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Label("Base map", systemImage: basemap.symbol)
            }
        }
        ToolbarItem {
            NavigationLink {
                SettingsScreen()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: {
                if !$0 {
                    selection = nil
                }
            }
        )
    }

    private var tierCounts: [PlaceTier: Int] {
        Dictionary(grouping: store.places, by: \.tier).mapValues(\.count)
    }

    private func select(_ result: MapSearchResult) {
        query = ""
        switch result {
        case let .place(place):
            selection = place.id
            camera = AtlasCameraRequest(box: store.frame(for: place).expanded(by: 0.15))
        case let .pointOfInterest(poi):
            selection = poi.placeID
            let pad = 0.02
            camera = AtlasCameraRequest(box: BoundingBox(
                south: poi.location.latitude - pad, west: poi.location.longitude - pad,
                north: poi.location.latitude + pad, east: poi.location.longitude + pad
            ))
        }
    }

    private func open(_ place: Place) {
        selection = nil
        path.append(place.id)
    }
}

/// Where a place's overview leads: its Unigrid guide for a national park, its leaflet for
/// everything else.
struct PlaceDestination: View {
    @Environment(\.referenceStore) private var store
    let placeID: UnigridsID

    var body: some View {
        if let place = store.place(placeID) {
            if place.tier.hasGuide, store.guide(for: place.id) != nil {
                ParkGuideScreen(place: place)
            } else {
                PlaceLeafletScreen(place: place)
            }
        } else {
            ContentUnavailableView(
                "Unknown place",
                systemImage: "questionmark.square.dashed",
                description: Text("This place is no longer in the dataset (\(placeID.rawValue)).")
            )
        }
    }
}

// MARK: - Region shortcuts

/// Alaska, Hawaii and the territories are one tap away (SPECIFICATION.md §5).
struct RegionShortcutBar: View {
    @Environment(\.unigrid) private var style
    let onSelect: (BoundingBox) -> Void

    private static let regions: [(String, BoundingBox)] = [
        ("Lower 48", BoundingBox(south: 24.5, west: -125, north: 49.5, east: -66.5)),
        ("Alaska", BoundingBox(south: 54.5, west: -168, north: 71.5, east: -137)),
        ("Hawaiʻi", BoundingBox(south: 18.8, west: -160.4, north: 22.3, east: -154.7)),
        ("Caribbean", BoundingBox(south: 17.6, west: -67.4, north: 18.6, east: -64.5)),
        ("Pacific", BoundingBox(south: -14.4, west: -170.9, north: -14.1, east: -169.4)),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Self.regions, id: \.0) { name, box in
                    Button {
                        onSelect(box)
                    } label: {
                        Text(name.uppercased())
                            .font(UnigridStyle.dataLabel)
                            .tracking(1.1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(style.bandInk)
                    Rectangle()
                        .fill(style.bandInkSecondary.opacity(0.4))
                        .frame(width: 1, height: 12)
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.hidden)
        .background(style.band)
    }
}

// MARK: - Legend

/// The key to the map, set as a brochure map's legend: shape for tier, and a count. It
/// doubles as the way into the filters.
struct MapLegend: View {
    @Environment(\.unigrid) private var style
    let filter: MapFilter
    let counts: [PlaceTier: Int]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ForEach(PlaceTier.allCases, id: \.self) { tier in
                    HStack(spacing: 5) {
                        PlaceMarker(tier: tier, tint: tint(for: tier), status: .none)
                        Text("\(counts[tier] ?? 0)")
                            .font(UnigridStyle.dataLabel)
                            .monospacedDigit()
                            .foregroundStyle(style.ink)
                    }
                    .opacity(filter.tiers.contains(tier) ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(style.panel)
            .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map key and filters")
        .accessibilityValue(
            PlaceTier.allCases
                .map { "\(counts[$0] ?? 0) \($0.name)" }
                .joined(separator: ", ")
        )
    }

    private func tint(for tier: PlaceTier) -> Color {
        let agency: Agency = switch tier {
        case .nationalPark, .npsUnit: .nps
        case .statePark: .stateAgency
        case .federalSite: .blm
        }
        return Color(AgencyInk.forPlace(agency: agency, tier: tier).value(style.scheme))
    }
}

// MARK: - Filters

struct MapFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    @Binding var filter: MapFilter
    let counts: [PlaceTier: Int]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PlaceTier.allCases, id: \.self) { tier in
                        Toggle(isOn: binding(for: tier)) {
                            HStack(spacing: 12) {
                                PlaceMarker(tier: tier, tint: legendTint(tier), status: .none)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tier.name)
                                        .font(UnigridStyle.rowTitle)
                                    Text("\(counts[tier] ?? 0) · \(tier.detail)")
                                        .font(UnigridStyle.rowDetail)
                                        .foregroundStyle(style.inkSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Kicker("Show")
                }

                Section {
                    Picker("Visits", selection: $filter.visits) {
                        ForEach(MapFilter.Visits.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Kicker("Your log")
                }

                Section {
                    LegendKey()
                } header: {
                    Kicker("Key")
                }
            }
            .paperPage()
            .navigationTitle("Map filters")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = .everything }
                        .disabled(!filter.isNarrowed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheetSize()
        .presentationDetents([.medium, .large])
    }

    private func binding(for tier: PlaceTier) -> Binding<Bool> {
        Binding(
            get: { filter.tiers.contains(tier) },
            set: { isOn in
                if isOn {
                    filter.tiers.insert(tier)
                } else {
                    filter.tiers.remove(tier)
                }
            }
        )
    }

    private func legendTint(_ tier: PlaceTier) -> Color {
        let agency: Agency = switch tier {
        case .nationalPark, .npsUnit: .nps
        case .statePark: .stateAgency
        case .federalSite: .blm
        }
        return Color(AgencyInk.forPlace(agency: agency, tier: tier).value(style.scheme))
    }
}

/// What filled, hollow and dashed mean, and which ink is whose.
struct LegendKey: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(status: .visited, text: "Filled: you have been")
            row(status: .none, text: "Hollow: not yet")
            row(status: .planned, text: "Dashed: on a trip you are planning")
            Hairline()
            ForEach(Self.inks, id: \.1) { ink, name in
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color(ink.value(style.scheme)))
                        .frame(width: 14, height: 8)
                    Text(name)
                        .font(UnigridStyle.rowDetail)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func row(status: PlaceMarker.Status, text: String) -> some View {
        HStack(spacing: 10) {
            PlaceMarker(
                tier: .nationalPark,
                tint: Color(AgencyInk.nationalPark.value(style.scheme)),
                status: status
            )
            Text(text)
                .font(UnigridStyle.rowDetail)
        }
    }

    private static let inks: [(AgencyInk, String)] = [
        (.nationalPark, "National Park Service"),
        (.stateAgency, "State parks"),
        (.blm, "Bureau of Land Management"),
        (.forestService, "US Forest Service"),
        (.fishAndWildlife, "US Fish and Wildlife Service"),
    ]
}

// MARK: - Search

enum MapSearchResult {
    case place(Place)
    case pointOfInterest(PointOfInterest)
}

/// Search covers parks, sights and visitor centres (SPECIFICATION.md §5).
struct MapSearchSuggestions: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let query: String
    let onSelect: (MapSearchResult) -> Void

    var body: some View {
        let places = store.search(query, limit: 8)
        let sights = store.searchPointsOfInterest(query, limit: 6)
        ForEach(places) { place in
            Button {
                onSelect(.place(place))
            } label: {
                HStack(spacing: 10) {
                    PlaceMarker(tier: place.tier, tint: style.agencyTint(for: place))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.name)
                            .font(UnigridStyle.rowTitle)
                        Text("\(place.designation) · \(place.statesDescription)")
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
        ForEach(sights) { poi in
            Button {
                onSelect(.pointOfInterest(poi))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: poi.kind == .visitorCentre ? "info.square" : "mappin.square")
                        .foregroundStyle(style.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(poi.name)
                            .font(UnigridStyle.rowTitle)
                        Text("\(poi.kind.name) · \(store.place(poi.placeID)?.name ?? "")")
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
    }
}

extension Coordinate {
    /// The boundary between the domain's own coordinate type and MapKit's.
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension BoundingBox {
    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: centre.clCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(north - south, 0.02),
                longitudeDelta: max(east - west, 0.02)
            )
        )
    }
}
