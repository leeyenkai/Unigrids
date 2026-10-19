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
    @Query private var visits: [Visit]

    let place: Place

    @State private var availableWidth: Double = 0
    @State private var showCheckIn = false
    @State private var showStamp = false
    @State private var showAddToTrip = false

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
        .background(style.page)
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width - (UnigridStyle.pageMargin * 2)
        } action: { width in
            availableWidth = width
        }
        .navigationTitle(place.name)
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .sheet(isPresented: $showStamp) { StampSheet(place: place) }
        .sheet(isPresented: $showAddToTrip) { AddToTripSheet(place: place) }
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
                                Text("No overview has been written for this place yet.")
                                    .font(UnigridStyle.prose)
                                    .foregroundStyle(style.inkSecondary)
                            }
                            OverviewFigures(place: place)
                            UnigridDataRow(label: "Managed by", value: place.agency.name)
                        }
                    }
                    if !centres.isEmpty {
                        VisitorCentresPanel(centres: centres)
                    }
                }
                VStack(spacing: UnigridStyle.gutter) {
                    UnigridPanel(title: "The place") {
                        ParkMapView(
                            place: place,
                            boundary: store.boundary(for: place.id),
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
                            onAddToTrip: { showAddToTrip = true }
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
        switch place.summarySource {
        case "National Park Service":
            [
                "Overview from the National Park Service. "
                    + "Outline from the NPS Land Resources Division.",
            ]
        default:
            [
                "Overview written for Unigrids. Outline and area from the USGS Protected Areas "
                    + "Database (PAD-US).",
            ]
        }
    }
}

extension EnvironmentValues {
    /// Set inside a leaflet, where the overview's "Open" action would only lead back here.
    @Entry var leafletMode = false
}
