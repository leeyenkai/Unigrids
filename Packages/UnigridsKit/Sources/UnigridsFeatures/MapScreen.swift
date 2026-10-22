import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The map the app opens on (SPECIFICATION.md §5): every covered place across the US —
/// national parks, every other NPS site, national forests and grasslands, wildlife
/// refuges, BLM lands, state parks, natural landmarks and scenic byways — each pin its
/// site type's pictogram, national parks outlined from the start and everything else
/// outlined as the camera comes in. Interstates, US routes and Amtrak lay over it on
/// request. Tapping a pin, a byway or anywhere inside an outline opens that place.
public struct MapScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var alerts: AlertsCenter?
    @Environment(TransportStore.self) private var transportStore: TransportStore?
    @Query private var visits: [Visit]
    @Query private var trips: [Trip]

    @State private var path = NavigationPath()
    @State private var selection: UnigridsID?
    @State private var camera: AtlasCameraRequest?
    @State private var filter = MapFilter.everything
    @State private var query = ""
    @State private var showKey = false
    @State private var showsUserLocation = false
    @State private var locating = false
    @AppStorage("map.basemap") private var basemap = AtlasBasemap.standard
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// On a phone the overview is a sheet over the bottom of the map; a place chosen from
    /// search is framed above it rather than under it.
    private var sheetInset: CGFloat {
        #if os(iOS)
            sizeClass == .compact ? 340 : 0
        #else
            0
        #endif
    }

    @AppStorage("map.layers") private var layersRaw = ""

    public init() {}

    private var index: VisitIndex {
        VisitIndex(visits: visits, trips: trips)
    }

    private var layers: Set<TransportLayer> {
        Set(layersRaw.split(separator: ",").compactMap { TransportLayer(rawValue: String($0)) })
    }

    private var layersBinding: Binding<Set<TransportLayer>> {
        Binding(
            get: { layers },
            set: { newValue in
                layersRaw = TransportLayer.allCases
                    .filter(newValue.contains)
                    .map(\.rawValue)
                    .joined(separator: ",")
            }
        )
    }

    private var atlasPlaces: [AtlasPlace] {
        let index = index
        let stamped = store.placesWithStampLocations
        return store.places.compactMap { place in
            let status = index.status(for: place.id)
            guard filter.includes(
                place,
                isVisited: status == .visited,
                hasStampLocation: stamped.contains(place.id)
            ) else { return nil }
            return AtlasPlace(
                place: place,
                status: status,
                alert: alerts?.mapLevel(for: place.npsParkCode)
            )
        }
    }

    private var selectedPlace: Place? {
        selection.flatMap(store.place)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            AtlasMapView(
                places: atlasPlaces,
                boundaries: store.boundaries,
                overviewBoundaries: store.overviewBoundaries,
                routes: store.routes,
                transport: transportStore?.network ?? .empty,
                layers: layers,
                selection: selection,
                camera: camera,
                basemap: basemap,
                // Imagery is dark whatever the scheme, so lines over it take the dark inks.
                ink: AtlasInk(
                    scheme: basemap == .standard ? style.scheme : .dark,
                    palette: style.palette
                ),
                showsUserLocation: showsUserLocation,
                onSelect: { selection = $0 },
                onRegionChange: { _ in }
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .overlay(alignment: .bottomLeading) {
                // Lifted clear of the base map's attribution, which MapKit draws in this
                // corner and which must stay legible.
                MapKeyButton(filter: filter, layers: layers) { showKey = true }
                    .padding(.leading, 12)
                    .padding(.bottom, 40)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                RegionShortcutBar { box in
                    camera = AtlasCameraRequest(box: box)
                }
            }
            .navigationTitle("Map")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Parks, forests, refuges, sights")
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
            .sheet(isPresented: $showKey) {
                MapKeySheet(
                    filter: $filter,
                    layers: layersBinding,
                    basemap: $basemap,
                    counts: typeCounts
                )
            }
            .navigationDestination(for: UnigridsID.self) { id in
                PlaceDestination(placeID: id)
            }
            .task(id: layers.isEmpty) {
                await loadTransportIfNeeded()
            }
            .task {
                await alerts?.refreshIfStale()
            }
            .onAppear(perform: applyDebugLaunch)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                showKey = true
            } label: {
                Label(
                    "Key and filters",
                    systemImage: filter.isNarrowed
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .badge(filter.narrowedCount)
        }
        ToolbarItem {
            MapLayersMenu(layers: layersBinding, basemap: $basemap)
        }
        ToolbarItem {
            Button {
                Task { await locate() }
            } label: {
                Label("Where am I", systemImage: showsUserLocation ? "location.fill" : "location")
            }
            .disabled(locating)
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

    private var typeCounts: [SiteType: Int] {
        Dictionary(grouping: store.places, by: \.siteType).mapValues(\.count)
    }

    private func loadTransportIfNeeded() async {
        guard !layers.isEmpty else { return }
        await transportStore?.load(from: store)
    }

    /// Centre on the reader, once. The location is used for the camera and the blue dot
    /// and never stored (SPECIFICATION.md §15).
    private func locate() async {
        locating = true
        defer { locating = false }
        guard let here = await OnSiteCheck().currentCoordinate() else { return }
        showsUserLocation = true
        let pad = 0.6
        camera = AtlasCameraRequest(box: BoundingBox(
            south: here.latitude - pad, west: here.longitude - pad * 1.4,
            north: here.latitude + pad, east: here.longitude + pad * 1.4
        ))
    }

    private func select(_ result: MapSearchResult) {
        query = ""
        switch result {
        case let .place(place):
            selection = place.id
            camera = AtlasCameraRequest(
                box: store.frame(for: place).expanded(by: 0.15), bottomInset: sheetInset
            )
        case let .pointOfInterest(poi):
            selection = poi.placeID
            let pad = 0.02
            camera = AtlasCameraRequest(
                box: BoundingBox(
                    south: poi.location.latitude - pad, west: poi.location.longitude - pad,
                    north: poi.location.latitude + pad, east: poi.location.longitude + pad
                ),
                bottomInset: sheetInset
            )
        }
    }

    private func applyDebugLaunch() {
        if let region = DebugLaunch.region {
            camera = AtlasCameraRequest(box: region, animated: false)
        }
        if let id = DebugLaunch.selection {
            selection = id
        }
        if let id = DebugLaunch.opens {
            path.append(id)
        }
        if DebugLaunch.showsKey {
            showKey = true
        }
    }

    private func open(_ place: Place) {
        selection = nil
        path.append(place.id)
    }
}

/// A place in a window of its own, on the Mac (SPECIFICATION.md §6: "a guide can open in
/// its own window beside the map").
public struct PlaceWindow: View {
    let placeID: UnigridsID?

    public init(placeID: UnigridsID?) {
        self.placeID = placeID
    }

    public var body: some View {
        NavigationStack {
            if let placeID {
                PlaceDestination(placeID: placeID)
                    .navigationDestination(for: UnigridsID.self) { id in
                        PlaceDestination(placeID: id)
                    }
            }
        }
        .frame(minWidth: 760, minHeight: 640)
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

// The key, filters and layers live in MapKey.swift.

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
                    SitePin(place: place)
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
