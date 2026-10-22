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
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.scenePhase) private var scenePhase
    @Query private var visits: [Visit]
    @Query private var trips: [Trip]

    @State private var path = NavigationPath()
    @State private var selection: UnigridsID?
    @State private var camera: AtlasCameraRequest?
    /// The filter, kept between launches: a map left showing only stamp locations
    /// should open that way, with the chip that says so.
    @AppStorage("map.filter") private var filterData = Data()
    @State private var query = ""
    @State private var showKey = false
    @State private var showsUserLocation = false
    @State private var locating = false
    @State private var locationProblem: LocationProblem?
    @State private var focus: AtlasFocus?
    /// The place the marked sight is in; choosing any other place clears the mark.
    @State private var focusPlace: UnigridsID?
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

    private var filter: MapFilter {
        filterData.isEmpty ? .everything
            : (try? JSONDecoder().decode(MapFilter.self, from: filterData)) ?? .everything
    }

    private var filterBinding: Binding<MapFilter> {
        Binding(
            get: { filter },
            set: { newValue in
                // Everything is stored as nothing, so a kind of place added in a later
                // release is not filtered out by a choice made before it existed.
                filterData = newValue == .everything
                    ? Data() : (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }

    private var atlasPlaces: [AtlasPlace] {
        let index = index
        let filter = filter
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
                focus: focus,
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
                VStack(alignment: .leading, spacing: 0) {
                    RegionShortcutBar { box in
                        camera = AtlasCameraRequest(box: box)
                    }
                    MapStatusChips(
                        filter: filter,
                        shown: filter.isNarrowed ? atlasPlaces.count : store.places.count,
                        total: store.places.count,
                        layersWanted: !layers.isEmpty,
                        onClear: { filterBinding.wrappedValue = .everything },
                        onRetryLayers: { Task { await loadTransportIfNeeded() } }
                    )
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
            .onChange(of: selection) {
                if selection != focusPlace {
                    focus = nil
                    focusPlace = nil
                }
            }
            .alert(
                locationProblem?.title ?? "",
                isPresented: Binding(
                    get: { locationProblem != nil },
                    set: {
                        if !$0 {
                            locationProblem = nil
                        }
                    }
                ),
                presenting: locationProblem
            ) { problem in
                if let settings = problem.settingsURL {
                    Button("Open Settings") { AppServices.openExternally(settings) }
                }
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
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
            .unigridsSheet(isPresented: $showKey) {
                MapKeySheet(
                    filter: filterBinding,
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
            .onChange(of: router?.pending, initial: true) { takeRoute() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
            SettingsToolbarItem()
        #endif
        ToolbarItem {
            Button {
                showKey = true
            } label: {
                Label("Key and filters", symbol: filter.isNarrowed ? .filtered : .filter)
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
                Label("Where am I", symbol: showsUserLocation ? .located : .locate)
            }
            .disabled(locating)
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
        guard let here = await OnSiteCheck().currentCoordinate() else {
            locationProblem = OnSiteCheck.isRefused ? .refused : .unavailable
            return
        }
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
            focus = nil
            focusPlace = nil
            selection = place.id
            camera = AtlasCameraRequest(
                box: store.frame(for: place).expanded(by: 0.15), bottomInset: sheetInset
            )
        case let .pointOfInterest(poi):
            focus = AtlasFocus(name: poi.name, coordinate: poi.location)
            focusPlace = poi.placeID
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

    /// A notification about a place — a new alert — opens its page.
    private func takeRoute() {
        guard scenePhase == .active, case let .place(id) = router?.pending else { return }
        router?.pending = nil
        selection = nil
        path = NavigationPath()
        path.append(UnigridsID(id))
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
                systemImage: UnigridsSymbol.unknownPlace.systemName,
                description: Text("This place is no longer in the dataset (\(placeID.rawValue)).")
            )
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
