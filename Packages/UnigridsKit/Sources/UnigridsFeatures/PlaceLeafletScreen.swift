import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// A place without a full guide — another NPS unit, a state park, a monument, a refuge —
/// as a one-panel leaflet in the same Unigrid as the guides: band, photograph, overview,
/// figures, the place on a map and what to do about it (SPECIFICATION.md §5, tiers 2–4).
///
/// A leaflet is a guide's smaller sibling, which is why it shares the guide's grid and
/// panels rather than having a look of its own.
struct PlaceLeafletScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openWindow) private var openWindow
    @Query private var visits: [Visit]

    let place: Place

    @State private var availableWidth: Double = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var trainAccess: TrainAccess?
    @Environment(TransportStore.self) private var transport: TransportStore?
    @State private var showCheckIn = false
    @State private var showStamp = false
    @State private var showAddToTrip = false
    @State private var showExplorer = false
    @State private var showBrochure = false

    private var columns: Int {
        min(
            UnigridGrid.columnCount(
                availableWidth: availableWidth,
                typeScale: UnigridStyle.typeScale(for: typeSize)
            ),
            2
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                UnigridTitleBand(
                    name: place.name,
                    designation: place.designation,
                    states: place.statesDescription
                )
                if let image = place.image {
                    GuideHero(image: image)
                }
                content
                    .padding(UnigridStyle.pageMargin)
            }
        }
        .scrollPosition($scrollPosition)
        .task(id: place.id) {
            trainAccess = await ByTrainPanel.access(to: place, store: store, transport: transport)
        }
        .task {
            if let offset = DebugLaunch.scrollOffset {
                try? await Task.sleep(for: .seconds(1.5))
                scrollPosition.scrollTo(y: offset)
            }
        }
        .background(style.page)
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width - (UnigridStyle.pageMargin * 2)
        } action: { width in
            availableWidth = width
        }
        .navigationTitle(place.name)
        .toolbarTitleDisplayMode(.inline)
        .unigridsSheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .unigridsSheet(isPresented: $showStamp) { StampSheet(place: place) }
        .unigridsSheet(isPresented: $showAddToTrip) { AddToTripSheet(place: place) }
        .explorer(isPresented: $showExplorer, place: place)
        .unigridsSheet(isPresented: $showBrochure) {
            BrochureScreen(place: place)
        }
        .toolbar {
            #if os(macOS)
                ToolbarItem {
                    Button { openWindow(value: place.id) } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }
            #endif
            ToolbarItem {
                Button { showExplorer = true } label: {
                    Label("Explore in 3D", symbol: .explore3D)
                }
            }
        }
    }

    private var content: some View {
        let centres = store.visitorCentres(in: place.id)
        let layout = columns > 1
            ? AnyLayout(HStackLayout(alignment: .top, spacing: UnigridStyle.gutter))
            : AnyLayout(VStackLayout(spacing: UnigridStyle.gutter))
        return VStack(spacing: UnigridStyle.gutter) {
            layout {
                VStack(spacing: UnigridStyle.gutter) {
                    UnigridPanel(title: "Overview") {
                        VStack(alignment: .leading, spacing: 14) {
                            VisitStatusLine(visits: visits.filter { $0.place == place.id }
                                .sorted { $0.date > $1.date })
                            if let summary = place.summary {
                                OverviewSummary(text: summary, source: place.summarySource)
                            } else {
                                Text(place.factualDescription)
                                    .font(UnigridStyle.prose)
                                    .foregroundStyle(style.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            OverviewFigures(place: place)
                            ManagerRow(place: place)
                        }
                    }
                    if !centres.isEmpty {
                        VisitorCentresPanel(centres: centres)
                    }
                    ByTrainPanel(place: place, access: trainAccess)
                    BrochurePanel(place: place) { showBrochure = true }
                }
                VStack(spacing: UnigridStyle.gutter) {
                    UnigridPanel(title: "The place") {
                        ParkMapView(
                            place: place,
                            boundary: store.boundary(for: place.id),
                            route: store.route(for: place.id),
                            sights: [],
                            centres: centres,
                            interactive: false
                        )
                        .frame(height: 300)
                        .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                    }
                    UnigridPanel(title: "Your visit") {
                        OverviewActions(
                            place: place,
                            hasGuide: false,
                            onOpen: { openInMaps(place) },
                            onCheckIn: { showCheckIn = true },
                            onStamp: { showStamp = true },
                            onAddToTrip: { showAddToTrip = true },
                            onExplore: { showExplorer = true }
                        )
                        .environment(\.leafletMode, true)
                    }
                }
            }
            GuideCreditsPanel(
                credits: credits,
                sources: [],
                photos: [place.image].compactMap(\.self)
            )
        }
    }

    private var credits: [String] {
        PlaceCredits.lines(for: place)
    }
}

extension EnvironmentValues {
    /// Set inside a leaflet, where the overview's "Open" action would only lead back here.
    @Entry var leafletMode = false
}

/// Who a place's data comes from, for the credits at the foot of its page. Each source
/// is credited for what it actually supplied.
enum PlaceCredits {
    static func lines(for place: Place) -> [String] {
        let written = place.summarySource == "Unigrids"
        switch place.kind {
        case .nationalPark, .npsUnit:
            return [
                (written ? "Overview written for Unigrids from National Park Service material. "
                    : "Overview from the National Park Service. ")
                    + "Outline from the NPS Land Resources Division.",
            ]
        case .statePark:
            return [
                "Overview written for Unigrids. Outline and area from the USGS Protected Areas "
                    + "Database (PAD-US).",
            ]
        case .nationalForest, .nationalGrassland:
            return [
                "Proclaimed boundary and area from the US Forest Service. No overview has been "
                    + "written for this place; the description is built from the boundary data.",
            ]
        case .wildlifeRefuge:
            return [
                written ? "Overview written for Unigrids. Outline from the USGS Protected Areas "
                    + "Database (PAD-US)."
                    : "Refuge boundary from the US Fish and Wildlife Service. No overview has been "
                    + "written for this refuge.",
            ]
        case .blmMonument, .blmConservationArea:
            return [
                written ? "Overview written for Unigrids. Outline from the USGS Protected Areas "
                    + "Database (PAD-US)."
                    : "Boundary from the Bureau of Land Management's National Conservation "
                    + "Lands data. No overview has been written for this place.",
            ]
        case .naturalLandmark:
            return [
                "Location and area from the National Park Service's National Natural Landmarks "
                    + "Program. Designation recognises a site; it does not open private land "
                    + "to visitors.",
            ]
        case .scenicByway:
            return [
                "Route and designation from the Federal Highway Administration's America's "
                    + "Byways data.",
            ]
        }
    }
}

/// Who runs a place, or for a landmark or a byway, which programme names it.
struct ManagerRow: View {
    let place: Place

    var body: some View {
        switch place.kind {
        case .naturalLandmark:
            UnigridDataRow(label: "Programme", value: "National Natural Landmarks (NPS)")
        case .scenicByway:
            UnigridDataRow(label: "Programme", value: "America's Byways (FHWA)")
        default:
            UnigridDataRow(label: "Managed by", value: place.agency.name)
        }
    }
}
