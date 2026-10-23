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
                        Label("Open in New Window", symbol: .newWindow)
                    }
                    .help("Open in New Window")
                }
            #endif
            ToolbarItem {
                Button { showExplorer = true } label: {
                    Label("Explore in 3D", symbol: .explore3D)
                }
                .help("Explore in 3D")
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
                            if place.summary != nil {
                                OverviewSummary(place: place)
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
                    if let code = place.npsParkCode, NPSAlerts.isConfigured {
                        AlertsPanel(parkCode: code)
                    }
                    if let info = place.visitorInfo {
                        VisitorInfoPanels(info: info)
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
                    if let visitation = place.visitation {
                        VisitationPanel(visitation: visitation)
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
/// is credited for what it actually supplied: the overview by who wrote it, the outline
/// by the agency that published it.
enum PlaceCredits {
    static func lines(for place: Place) -> [String] {
        [overview(place), outline(place)].compactMap(\.self)
    }

    private static func overview(_ place: Place) -> String? {
        switch place.summary == nil ? nil : place.summarySource {
        case "Unigrids": "Overview written for Unigrids."
        case "Wikipedia": (place.summaryCredit ?? "Adapted from Wikipedia") + "."
        case let source?: "Overview from the \(source)."
        case nil: "No overview has been written for this place; its description is built "
            + "from the boundary data."
        }
    }

    private static func outline(_ place: Place) -> String {
        switch place.kind {
        case .nationalPark, .npsUnit:
            "Outline from the NPS Land Resources Division."
                + (place.visitation == nil ? ""
                    : " Visits from NPS Visitor Use Statistics, CC0.")
        case .statePark:
            "Outline and area from the USGS Protected Areas Database (PAD-US)."
        case .nationalForest, .nationalGrassland:
            "Proclaimed boundary and area from the US Forest Service."
        case .wildlifeRefuge:
            "Refuge boundary from the US Fish and Wildlife Service and PAD-US."
        case .blmMonument, .blmConservationArea:
            "Boundary from the Bureau of Land Management's National Conservation Lands data."
        case .naturalLandmark:
            "Location and area from the National Park Service's National Natural Landmarks "
                + "Program. Designation recognises a site; it does not open private land "
                + "to visitors."
        case .scenicByway:
            "Route and designation from the Federal Highway Administration's America's "
                + "Byways data."
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
            // A state park names the body that runs it, as PAD-US does.
            UnigridDataRow(label: "Managed by", value: place.managedBy ?? place.agency.name)
        }
    }
}
