import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// 3D exploration (SPECIFICATION.md §7): Apple's terrain and imagery with the place's
/// structure drawn on top — outline, numbered sights, visitor centres and campgrounds,
/// trails — a camera that flies to whatever is chosen and opens its card, and a guided
/// fly-through that visits the sights in rank order and circles each one.
///
/// Every place has one: a national park gets its sights, trails and tour; a forest, a
/// refuge or a byway gets its outline or its road, in 3D. Online only — Apple's 3D needs
/// a connection.
struct ParkExplorer: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss

    let place: Place
    /// What to open on: a trail from its page, say. The whole place otherwise.
    var initialFocus: ExplorerFocus?

    @State private var position: MapCameraPosition = .automatic
    @State private var focus: ExplorerFocus?
    @State private var tour: TourProgress?
    @State private var tourTask: Task<Void, Never>?
    @State private var visible: BoundingBox?
    @State private var showList = false
    @State private var checkIn: Set<UnigridsID>?
    @AppStorage("explorer.style") private var mapStyle = ExplorerStyle.hybrid
    @AppStorage("explorer.trails") private var showTrails = true
    @AppStorage("explorer.facilities") private var showFacilities = true

    private var sights: [PointOfInterest] {
        store.sights(in: place.id)
    }

    private var facilities: [PointOfInterest] {
        store.pointsOfInterest(in: place.id)
            .filter { $0.kind == .visitorCentre || $0.kind == .campground }
    }

    private var trails: [Trail] {
        store.trails(in: place.id).sorted { $0.lengthMetres > $1.lengthMetres }
    }

    private var frame: BoundingBox {
        store.frame(for: place)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let wide = proxy.size.width >= 820
                HStack(spacing: 0) {
                    if wide {
                        ExplorerList(
                            place: place,
                            sights: sights,
                            trails: trails,
                            facilities: facilities,
                            focus: focus,
                            visible: visible,
                            onSelect: select
                        )
                        .frame(width: 300)
                        Rectangle().fill(style.rule).frame(width: 1)
                    }
                    mapArea(wide: wide)
                }
            }
            .navigationTitle(place.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onAppear {
                show(ExplorerCamera.overview(of: frame), animation: nil)
                if let initialFocus {
                    select(initialFocus)
                } else if let sight = DebugLaunch.exploreSight {
                    select(.sight(sight))
                } else if DebugLaunch.startsTour, !sights.isEmpty {
                    restartTour(at: 0)
                }
            }
            .onDisappear { stopTour() }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    ExplorerList(
                        place: place,
                        sights: sights,
                        trails: trails,
                        facilities: facilities,
                        focus: focus,
                        visible: visible
                    ) { item in
                        showList = false
                        select(item)
                    }
                    .navigationTitle("In \(place.name)")
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showList = false }
                        }
                    }
                }
                .sheetSize()
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: checkInBinding) {
                CheckInSheet(place: place, preselecting: checkIn ?? [])
            }
        }
    }

    // MARK: Map

    private func mapArea(wide: Bool) -> some View {
        ExplorerMap(
            place: place,
            boundary: store.boundary(for: place.id),
            route: store.route(for: place.id),
            sights: sights,
            facilities: showFacilities ? facilities : [],
            trails: showTrails ? trails : [],
            focus: focus,
            mapStyle: mapStyle,
            position: $position,
            onSelect: select,
            onCameraChange: { visible = $0 }
        )
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let tour {
                    TourBar(
                        progress: tour,
                        sight: sights.indices.contains(tour.index) ? sights[tour.index] : nil,
                        onPrevious: { restartTour(at: tour.index - 1) },
                        onNext: { restartTour(at: tour.index + 1) },
                        onPause: { pauseTour() },
                        onResume: { restartTour(at: tour.index) },
                        onStop: { stopTour(returnToOverview: true) }
                    )
                }
                if let focus, tour == nil || tour?.isPaused == true {
                    card(for: focus)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !wide, focus == nil, tour == nil, !sights.isEmpty {
                    SightStrip(sights: sights, current: nil) { index in
                        select(.sight(sights[index].id))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: focus)
        }
    }

    @ViewBuilder
    private func card(for focus: ExplorerFocus) -> some View {
        switch focus {
        case let .sight(id):
            if let index = sights.firstIndex(where: { $0.id == id }) {
                SightCard(
                    sight: sights[index],
                    number: index + 1,
                    count: sights.count,
                    onCheckIn: { checkIn = [id] },
                    onPrevious: index > 0 ? { select(.sight(sights[index - 1].id)) } : nil,
                    onNext: index + 1 < sights.count
                        ? { select(.sight(sights[index + 1].id)) } : nil,
                    onClose: { self.focus = nil }
                )
            }
        case let .facility(id):
            if let poi = facilities.first(where: { $0.id == id }) {
                FacilityCard(poi: poi, onCheckIn: { checkIn = [id] }) { self.focus = nil }
            }
        case let .trail(id):
            if let trail = trails.first(where: { $0.id == id }) {
                ExplorerTrailCard(trail: trail, sights: sights) { self.focus = nil }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem {
            Menu {
                Picker("Imagery", selection: $mapStyle) {
                    ForEach(ExplorerStyle.allCases) { option in
                        Label(option.name, systemImage: option.symbol).tag(option)
                    }
                }
                Toggle(isOn: $showTrails) {
                    Label("Trails", systemImage: "figure.hiking")
                }
                .disabled(trails.isEmpty)
                Toggle(isOn: $showFacilities) {
                    Label("Visitor centres and campgrounds", systemImage: "info.square")
                }
                .disabled(facilities.isEmpty)
            } label: {
                Label("Layers", systemImage: "square.3.layers.3d")
            }
        }
        ToolbarItem {
            Button {
                stopTour()
                focus = nil
                show(ExplorerCamera.overview(of: frame))
            } label: {
                Label("Whole place", systemImage: "arrow.counterclockwise")
            }
        }
        ToolbarItem {
            Button { showList = true } label: {
                Label("List", systemImage: "list.number")
            }
            .disabled(sights.isEmpty && trails.isEmpty && facilities.isEmpty)
        }
        if !sights.isEmpty {
            ToolbarItem {
                Button {
                    if tour == nil {
                        restartTour(at: 0)
                    } else {
                        stopTour(returnToOverview: true)
                    }
                } label: {
                    Label(
                        tour == nil ? "Fly-through" : "End fly-through",
                        systemImage: tour == nil ? "play.fill" : "stop.fill"
                    )
                }
            }
        }
    }

    private var checkInBinding: Binding<Bool> {
        Binding(get: { checkIn != nil }, set: {
            if !$0 {
                checkIn = nil
            }
        })
    }

    // MARK: Camera

    private func select(_ item: ExplorerFocus) {
        stopTour()
        focus = item
        switch item {
        case let .sight(id):
            if let sight = sights.first(where: { $0.id == id }) {
                show(ExplorerCamera.sight(sight.location, in: frame))
            }
        case let .facility(id):
            if let poi = facilities.first(where: { $0.id == id }) {
                show(ExplorerCamera.sight(poi.location, in: frame))
            }
        case let .trail(id):
            let path = trails.first { $0.id == id }?.paths.max { $0.count < $1.count }
            if let shot = path.flatMap(ExplorerCamera.trail) {
                show(shot)
            }
        }
    }

    private func show(
        _ shot: ExplorerCamera.Shot,
        animation: Animation? = .easeInOut(duration: 2.5)
    ) {
        let camera = MapCamera(
            centerCoordinate: shot.centre.clCoordinate,
            distance: shot.distance,
            heading: shot.heading,
            pitch: shot.pitch
        )
        if let animation {
            withAnimation(animation) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }

    // MARK: Fly-through

    /// Visit the sights in rank order from `index`: fly in, circle a quarter turn, move on.
    /// Pausing keeps the place in the tour; the sight's card opens while it waits.
    private func restartTour(at index: Int) {
        tourTask?.cancel()
        let start = min(max(index, 0), max(sights.count - 1, 0))
        tour = TourProgress(index: start, count: sights.count, isPaused: false)
        focus = nil
        let sights = sights
        let frame = frame
        tourTask = Task { @MainActor in
            for current in start ..< sights.count {
                tour?.index = current
                let shot = ExplorerCamera.sight(sights[current].location, in: frame)
                show(shot, animation: .easeInOut(duration: 3.6))
                guard await pause(3.8) else { return }
                for heading in ExplorerCamera.orbit(from: shot.heading) {
                    let step = ExplorerCamera.Shot(
                        centre: shot.centre, distance: shot.distance,
                        heading: heading, pitch: shot.pitch
                    )
                    show(step, animation: .linear(duration: 1.7))
                    guard await pause(1.7) else { return }
                }
            }
            tour = nil
            show(ExplorerCamera.overview(of: frame), animation: .easeInOut(duration: 3))
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func pauseTour() {
        tourTask?.cancel()
        tourTask = nil
        guard var progress = tour else { return }
        progress.isPaused = true
        tour = progress
        if sights.indices.contains(progress.index) {
            focus = .sight(sights[progress.index].id)
        }
    }

    private func stopTour(returnToOverview: Bool = false) {
        tourTask?.cancel()
        tourTask = nil
        guard tour != nil else { return }
        tour = nil
        if returnToOverview {
            show(ExplorerCamera.overview(of: frame))
        }
    }
}

extension View {
    /// Present the 3D explorer: full screen on iPhone and iPad, a large sheet on the Mac.
    func explorer(
        isPresented: Binding<Bool>,
        place: Place,
        focus: ExplorerFocus? = nil
    ) -> some View {
        #if os(iOS)
            fullScreenCover(isPresented: isPresented) {
                ParkExplorer(place: place, initialFocus: focus)
            }
        #else
            sheet(isPresented: isPresented) {
                ParkExplorer(place: place, initialFocus: focus)
                    .frame(minWidth: 1100, minHeight: 760)
            }
        #endif
    }
}

/// What the explorer has in focus.
enum ExplorerFocus: Hashable {
    case sight(UnigridsID)
    case facility(UnigridsID)
    case trail(UnigridsID)
}

/// Where a fly-through is.
struct TourProgress: Equatable {
    var index: Int
    let count: Int
    var isPaused: Bool
}

/// The explorer's imagery.
enum ExplorerStyle: String, CaseIterable, Identifiable {
    case satellite
    case hybrid
    case map

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .satellite: "Satellite"
        case .hybrid: "Satellite with labels"
        case .map: "Map"
        }
    }

    var symbol: String {
        switch self {
        case .satellite: "globe.americas.fill"
        case .hybrid: "globe.americas"
        case .map: "map"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .map: .standard(
                elevation: .realistic,
                emphasis: .muted,
                pointsOfInterest: .excludingAll
            )
        }
    }
}

// MARK: - The map

// MARK: - The list

// MARK: - Cards
