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

    let place: Place

    @State private var availableWidth: Double = 0
    @State private var showCheckIn = false
    @State private var showStamp = false
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
                    page(guide)
                } else {
                    missingGuide
                }
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
        .toolbar {
            ToolbarItem {
                Button { showCheckIn = true } label: {
                    Label("Check in", systemImage: "mappin.and.ellipse")
                }
            }
            ToolbarItem {
                Button { showStamp = true } label: {
                    Label { Text("Stamp") } icon: { StampIcon() }
                }
            }
        }
        .sheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .sheet(isPresented: $showStamp) { StampSheet(place: place) }
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
            hasTrails: !trails.isEmpty
        )

        return VStack(spacing: UnigridStyle.gutter) {
            ForEach(
                Array(UnigridGrid.rows(panels: panels, columnCount: columnCount).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(alignment: .top, spacing: UnigridStyle.gutter) {
                    ForEach(row) { panel in
                        view(for: panel, guide: guide, sights: sights, centres: centres)
                    }
                }
            }

            // The brochure map is public domain and interactive in the finished guide
            // (§6, panel 5). It needs a checked asset per park from the pipeline's package
            // step, so until then the panel says what it is waiting for.
            if guide.mapImage == nil {
                UnigridPendingPanel(
                    title: "Brochure map",
                    explanation: "The park's official brochure map, interactive, with "
                        + "tappable visitor centres and sights. It ships once the data "
                        + "pipeline has confirmed a public-domain asset for this park."
                )
            }

            GuideCreditsPanel(credits: guide.credits, sources: guide.sources)
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
        case .majorSights:
            MajorSightsPanel(
                sights: sights,
                notes: guide.sightNotes,
                seenIDs: seenPointOfInterestIDs
            )
        case .visitorCentres:
            VisitorCentresPanel(centres: centres)
        case .trailHighlights:
            TrailHighlightsPanel(trails: store.trails(in: place.id))
        case .planYourVisit:
            PlanYourVisitPanel(plan: guide.planYourVisit)
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
