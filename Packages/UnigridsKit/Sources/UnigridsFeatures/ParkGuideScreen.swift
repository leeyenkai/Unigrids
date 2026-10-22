import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The app's signature screen: a native, interactive guide laid out like a Unigrid
/// brochure (SPECIFICATION.md §6).
///
/// The panels come from the content, in template order, and the grid decides how many
/// columns they sit in. Larger type takes columns away rather than shrinking the text —
/// that rule lives in `UnigridGrid`, and honouring it is why this view measures its own
/// width.
public struct ParkGuideScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    let place: Place

    @State private var availableWidth: Double = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var trainAccess: TrainAccess?
    @Environment(TransportStore.self) private var transport: TransportStore?
    @State private var showCheckIn = false
    @State private var showStamp = false
    @State private var showAddToTrip = false
    @State private var showExplorer = false
    @State private var showParkMap = false
    @State private var showBrochure = false
    @Query private var visits: [Visit]

    public init(place: Place) {
        self.place = place
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                UnigridTitleBand(
                    name: place.name,
                    designation: place.designation,
                    states: place.statesDescription
                )
                if let guide = store.guide(for: place.id) {
                    if let hero = guide.hero {
                        GuideHero(image: hero)
                    }
                    page(guide)
                } else {
                    missingGuide
                }
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
        .toolbar { toolbar }
        .unigridsSheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .unigridsSheet(isPresented: $showStamp) { StampSheet(place: place) }
        .unigridsSheet(isPresented: $showAddToTrip) { AddToTripSheet(place: place) }
        .explorer(isPresented: $showExplorer, place: place)
        .parkMap(isPresented: $showParkMap, place: place)
        .unigridsSheet(isPresented: $showBrochure) {
            BrochureScreen(place: place)
        }
        .onAppear {
            if DebugLaunch.explores {
                showExplorer = true
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
            ToolbarItem {
                Button { openWindow(value: place.id) } label: {
                    Label("Open in New Window", symbol: .newWindow)
                }
            }
        #endif
        ToolbarItem {
            Button { showExplorer = true } label: {
                Label("Explore in 3D", symbol: .explore3D)
            }
        }
        #if os(iOS)
            // An iPhone's bar holds 3D and one menu; the page's own actions panel has the
            // rest too.
            if sizeClass == .compact {
                ToolbarItem {
                    Menu {
                        actions
                    } label: {
                        Label("More", symbol: .details)
                    }
                }
            } else {
                ToolbarItemGroup { actions }
            }
        #else
            ToolbarItemGroup { actions }
        #endif
    }

    @ViewBuilder
    private var actions: some View {
        Button { showCheckIn = true } label: {
            Label("Check in", symbol: .checkIn)
        }
        Button { showStamp = true } label: {
            Label { Text("Stamp") } icon: { StampIcon() }
        }
        Button { showAddToTrip = true } label: {
            Label("Add to trip", symbol: .addToTrip)
        }
        if store.documents(for: place.id)?.documents.isEmpty == false {
            Button { showBrochure = true } label: {
                Label("Official brochure", symbol: .brochure)
            }
        }
        if hasPack {
            Button { showParkMap = true } label: {
                Label("Park map", symbol: .parkMap)
            }
        }
    }

    /// Whether the app carries this park's offline map.
    private var hasPack: Bool {
        OfflinePackCatalogue.bundled.pack(for: place.id) != nil
    }

    // MARK: - Layout

    private var columnCount: Int {
        UnigridGrid.columnCount(
            availableWidth: availableWidth,
            typeScale: UnigridStyle.typeScale(for: typeSize)
        )
    }

    private func page(_ guide: GuideContent) -> some View {
        let sights = store.sights(in: place.id)
        let centres = store.visitorCentres(in: place.id)
        let trails = store.trails(in: place.id)
        let panels = guide.panels(
            placeHasFacts: !place.facts.isEmpty,
            sightCount: sights.count,
            visitorCentreCount: centres.count,
            hasTrails: !trails.isEmpty,
            hasMap: store.boundary(for: place.id) != nil || !sights.isEmpty,
            showsAlerts: place.npsParkCode != nil && NPSAlerts.isConfigured
        )
        // The hero sits full-bleed under the band, not on the grid.
        .filter {
            if case .hero = $0 {
                false
            } else {
                true
            }
        }

        return VStack(spacing: UnigridStyle.gutter) {
            if let summary = place.summary, place.summarySource == "Unigrids" {
                GuideStandfirst(text: summary)
            }
            ForEach(
                Array(UnigridGrid.rows(panels: panels, columnCount: columnCount).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(alignment: .top, spacing: UnigridStyle.gutter) {
                    ForEach(row) { panel in
                        view(for: panel, guide: guide, sights: sights, centres: centres)
                    }
                }
                // The row's height is its tallest panel's, and the others stretch to it.
                .fixedSize(horizontal: false, vertical: true)
            }

            ByTrainPanel(place: place, access: trainAccess)

            BrochurePanel(place: place) { showBrochure = true }

            GuideActionsPanel(
                onCheckIn: { showCheckIn = true },
                onStamp: { showStamp = true },
                onAddToTrip: { showAddToTrip = true },
                officialURL: place.officialURL
            )

            GuideCreditsPanel(
                credits: guide.credits,
                sources: guide.sources,
                photos: [guide.hero].compactMap(\.self) + guide.gallery
            )
        }
        .padding(UnigridStyle.pageMargin)
    }

    @ViewBuilder
    private func view(
        for panel: GuidePanel,
        guide: GuideContent,
        sights: [PointOfInterest],
        centres: [PointOfInterest]
    ) -> some View {
        switch panel {
        case let .hero(image), let .map(image):
            GuideImagePanel(image: image)
        case .atAGlance:
            AtAGlancePanel(facts: place.facts)
        case .story:
            StoryPanel(paragraphs: guide.story)
        case .gallery:
            GalleryPanel(images: guide.gallery)
        case .parkMap:
            ParkMapPanel(
                place: place,
                sights: sights,
                centres: centres,
                onParkMap: hasPack ? { showParkMap = true } : nil
            ) {
                showExplorer = true
            }
        case .majorSights:
            MajorSightsPanel(
                sights: sights,
                notes: guide.sightNotes,
                seenIDs: seenPointOfInterestIDs
            )
        case .visitorCentres:
            VisitorCentresPanel(centres: centres)
        case .trailHighlights:
            TrailHighlightsPanel(
                place: place, trails: store.trails(in: place.id), named: guide.trailHighlightIDs
            )
        case .alerts:
            AlertsPanel(parkCode: place.npsParkCode ?? "")
        case .planYourVisit:
            PlanYourVisitPanel(
                plan: guide.planYourVisit,
                fees: guide.fees,
                hours: guide.operatingHours
            )
        case .weather:
            WeatherPanel(place: place, note: guide.weather)
        case .gettingThere:
            NotePanel(
                panel: .gettingThere,
                text: guide.directions ?? "",
                source: "National Park Service"
            )
        case .chronology:
            ChronologyPanel(entries: guide.chronology)
        case .safetyAndRegulations:
            SafetyPanel(safety: guide.safety, regulations: guide.regulations)
        case .creditsAndSources:
            // Drawn once across the full width at the foot of the page, not on the grid.
            EmptyView()
        }
    }

    private var missingGuide: some View {
        ContentUnavailableView(
            "Guide not available",
            systemImage: "book.closed",
            description: Text("No guide content shipped for \(place.name).")
        )
        .padding(40)
    }

    /// Sights the user has already checked in at, which the guide shows with a tick.
    private var seenPointOfInterestIDs: Set<UnigridsID> {
        let checkIns = visits
            .filter { $0.place == place.id }
            .flatMap { $0.checkIns ?? [] }
        return Set(checkIns.map(\.target.id))
    }
}

/// The hero photograph, full-bleed beneath the band, with its credit.
struct GuideHero: View {
    @Environment(\.unigrid) private var style
    let image: GuideImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlacePhoto(image: image, aspectRatio: 2.1, maxPoints: 1400)
                .frame(maxHeight: 520)
                .clipped()
            PhotoCredit(image: image)
                .padding(.horizontal, UnigridStyle.pageMargin)
        }
    }
}

/// The guide's opening paragraph, set large across the page as a brochure sets its
/// standfirst.
struct GuideStandfirst: View {
    @Environment(\.unigrid) private var style
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .serif))
            .foregroundStyle(style.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
