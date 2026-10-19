import MapKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// One small view per panel of the guide template (SPECIFICATION.md §6). Splitting them
// out keeps `ParkGuideScreen` a thin switch over the panel list, and each panel readable
// on its own (AGENTS.md §3).

/// Panel 3: the figures a guide opens with. Absent figures render as absent.
struct AtAGlancePanel: View {
    let facts: PlaceFacts

    var body: some View {
        UnigridPanel(title: GuidePanel.atAGlance.title) {
            VStack(alignment: .leading, spacing: 12) {
                if let year = facts.establishedYear {
                    UnigridDataRow(label: "Established as a national park", value: String(year))
                }
                if let acres = facts.areaAcres {
                    UnigridDataRow(label: "Area", value: UnigridsFormat.area(acres: acres))
                }
                if let range = UnigridsFormat.elevationRange(
                    lowest: facts.lowestElevationMetres,
                    highest: facts.highestElevationMetres
                ) {
                    UnigridDataRow(label: "Elevation", value: range)
                }
                if let annual = facts.annualVisits {
                    UnigridDataRow(
                        label: facts.annualVisitsYear.map { "Recreation visits, \($0)" }
                            ?? "Annual visits",
                        value: UnigridsFormat.visitors(annual)
                    )
                }
                if let fee = facts.entranceFee {
                    UnigridDataRow(label: "Entrance fee", value: fee)
                }
                if !facts.bestSeasons.isEmpty {
                    UnigridDataRow(
                        label: "Best seasons",
                        value: facts.bestSeasons.map(\.name).joined(separator: ", ")
                    )
                }
                if let time = facts.suggestedTime {
                    UnigridDataRow(label: "Suggested time", value: time)
                }
            }
        }
    }
}

/// Panel 4: three or four paragraphs on geology, ecology and history.
struct StoryPanel: View {
    @Environment(\.unigrid) private var style
    let paragraphs: [String]

    var body: some View {
        UnigridPanel(title: GuidePanel.story.title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The gallery: the park's further NPS photographs, each with its credit, opening full
/// screen on a tap.
struct GalleryPanel: View {
    @Environment(\.unigrid) private var style
    let images: [GuideImage]

    @State private var enlarged: GuideImage?

    var body: some View {
        UnigridPanel(title: GuidePanel.gallery.title) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 10, alignment: .top)],
                spacing: 14
            ) {
                ForEach(images, id: \.self) { image in
                    Button {
                        enlarged = image
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            PlacePhoto(image: image, aspectRatio: 4 / 3, maxPoints: 420)
                            PhotoCredit(image: image)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $enlarged) { image in
            PhotoViewer(image: image)
        }
    }
}

/// One photograph, as large as the screen allows, with its credit.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    let image: GuideImage

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                PlacePhoto(image: image, aspectRatio: 3 / 2, maxPoints: 1600)
                PhotoCredit(image: image)
                    .padding(.horizontal, 16)
                if let alt = image.altText {
                    Text(alt)
                        .font(UnigridStyle.proseSmall)
                        .foregroundStyle(style.inkSecondary)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
            .background(style.page)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheetSize(width: 900, height: 700)
    }
}

/// Panel 5: the park drawn — its outline, numbered sights and visitor centres — with the
/// way into the 3D explorer.
struct ParkMapPanel: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let place: Place
    let sights: [PointOfInterest]
    let centres: [PointOfInterest]
    let onExplore: () -> Void

    var body: some View {
        UnigridPanel(title: GuidePanel.parkMap.title) {
            VStack(alignment: .leading, spacing: 12) {
                ParkMapView(
                    place: place,
                    boundary: store.boundary(for: place.id),
                    sights: sights,
                    centres: centres,
                    interactive: false
                )
                .frame(height: 340)
                .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                .onTapGesture(perform: onExplore)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the park in 3D")

                Button(action: onExplore) {
                    Label("Explore in 3D", systemImage: "view.3d")
                }
                .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
            }
        }
    }
}

/// A park on a map: tinted outline, numbered sights in rank order, visitor centres as
/// squares. Shared by the guide's map panel and the explorer.
struct ParkMapView: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let boundary: PlaceBoundary?
    let sights: [PointOfInterest]
    let centres: [PointOfInterest]
    var interactive = true
    var position: Binding<MapCameraPosition>?
    var mapStyle: MapStyle = .standard(
        elevation: .realistic,
        emphasis: .muted,
        pointsOfInterest: .excludingAll
    )

    @State private var fallbackPosition: MapCameraPosition = .automatic

    var body: some View {
        let tint = style.agencyTint(for: place)
        Map(position: position ?? $fallbackPosition, interactionModes: interactive ? .all : []) {
            if let boundary {
                ForEach(Array(boundary.polygons.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.exterior.map(\.clCoordinate))
                        .foregroundStyle(tint.opacity(0.14))
                        .stroke(tint, lineWidth: 1.6)
                }
            }
            ForEach(Array(sights.enumerated()), id: \.element.id) { offset, sight in
                Annotation(sight.name, coordinate: sight.location.clCoordinate) {
                    SightNumber(number: offset + 1)
                }
                .annotationTitles(interactive ? .automatic : .hidden)
            }
            ForEach(centres) { centre in
                Annotation(centre.name, coordinate: centre.location.clCoordinate) {
                    Rectangle()
                        .fill(style.panel)
                        .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 2) }
                        .frame(width: 11, height: 11)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        .onAppear {
            if position == nil {
                fallbackPosition = .rect(MKMapRect(box: frame.expanded(by: 0.08)))
            }
        }
    }

    private var frame: BoundingBox {
        if let extent = boundary?.extent {
            return extent
        }
        let points = (sights + centres).map(\.location) + [place.centre]
        return BoundingBox.enclosing(points)?.expanded(by: 0.3)
            ?? BoundingBox(
                south: place.centre.latitude - 0.2, west: place.centre.longitude - 0.2,
                north: place.centre.latitude + 0.2, east: place.centre.longitude + 0.2
            )
    }
}

/// A sight's number on a map, in the black square the guide's list uses.
struct SightNumber: View {
    @Environment(\.unigrid) private var style
    let number: Int
    var isSelected = false

    var body: some View {
        Text("\(number)")
            .font(.custom("HelveticaNeue-Bold", size: 12))
            .foregroundStyle(isSelected ? style.onAccent : style.bandInk)
            .frame(width: 22, height: 22)
            .background(isSelected ? style.accent : style.band)
            .overlay { Rectangle().strokeBorder(style.bandInk, lineWidth: 1) }
    }
}

/// Panel 6: the ranked sights, with a seen-it check fed by the log.
struct MajorSightsPanel: View {
    let sights: [PointOfInterest]
    let notes: [String: String]
    let seenIDs: Set<UnigridsID>

    var body: some View {
        UnigridPanel(title: GuidePanel.majorSights.title) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(sights.enumerated()), id: \.element.id) { offset, sight in
                    UnigridNumberedItem(
                        number: offset + 1,
                        title: sight.name,
                        detail: notes[sight.id.rawValue] ?? sight.summary,
                        isSeen: seenIDs.contains(sight.id)
                    )
                }
            }
        }
    }
}

/// Panel 7: visitor centres, with hours and a mark where a passport stamp lives.
struct VisitorCentresPanel: View {
    @Environment(\.unigrid) private var style
    let centres: [PointOfInterest]

    var body: some View {
        UnigridPanel(title: GuidePanel.visitorCentres.title) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(centres) { centre in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(centre.name)
                                .font(UnigridStyle.itemTitle)
                                .foregroundStyle(style.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if centre.hasStamp {
                                StampIcon()
                                    .foregroundStyle(style.inkSecondary)
                                    .accessibilityLabel("Has a passport stamp")
                            }
                        }
                        if let hours = centre.hours {
                            Text(hours)
                                .font(UnigridStyle.dataLabel)
                                .foregroundStyle(style.inkSecondary)
                        }
                        if let summary = centre.summary {
                            Text(summary)
                                .font(UnigridStyle.prose)
                                .foregroundStyle(style.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if centre.id != centres.last?.id {
                        Hairline()
                    }
                }
            }
        }
    }
}

/// Panel 8: the park's top trails, linking into the catalogue.
struct TrailHighlightsPanel: View {
    let trails: [Trail]

    var body: some View {
        UnigridPanel(title: GuidePanel.trailHighlights.title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(trails) { trail in
                    UnigridDataRow(
                        label: trail.name,
                        value: UnigridsFormat.distance(metres: trail.lengthMetres)
                    )
                }
            }
        }
    }
}

/// Panel 9: entrances, fees, reservations, permits, camping, lodging and closures.
struct PlanYourVisitPanel: View {
    @Environment(\.unigrid) private var style
    let plan: PlanYourVisit
    let fees: [EntranceFee]
    let hours: String?

    var body: some View {
        UnigridPanel(title: GuidePanel.planYourVisit.title) {
            VStack(alignment: .leading, spacing: 14) {
                if let hours {
                    GuideNote(label: "Hours", text: hours)
                }
                if !fees.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        GuideFieldLabel("Entrance fees")
                        ForEach(fees) { fee in
                            HStack(alignment: .firstTextBaseline) {
                                Text(fee.title)
                                    .font(UnigridStyle.dataValue)
                                    .foregroundStyle(style.ink)
                                Spacer(minLength: 8)
                                Text(fee.cost)
                                    .font(.custom(
                                        "HelveticaNeue-Bold",
                                        size: 15,
                                        relativeTo: .body
                                    ))
                                    .foregroundStyle(style.ink)
                                    .monospacedDigit()
                            }
                        }
                        Text(
                            "Fees as the NPS publishes them. "
                                + "Annual and lifetime passes cover entry."
                        )
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                    }
                }
                GuideLabelledList(label: "Entrances", items: plan.entrances)
                if let reservations = plan.reservations {
                    GuideNote(label: "Reservations", text: reservations)
                }
                GuideLabelledList(label: "Permits", items: plan.permits)
                GuideLabelledList(label: "Camping", items: plan.camping)
                GuideLabelledList(label: "Lodging", items: plan.lodging)
                GuideLabelledList(label: "Seasonal closures", items: plan.seasonalClosures)
            }
        }
    }
}

/// A panel holding one of the NPS's own notes — weather, directions — with its source.
struct NotePanel: View {
    @Environment(\.unigrid) private var style
    let panel: GuidePanel
    let text: String
    let source: String

    var body: some View {
        UnigridPanel(title: panel.title) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(UnigridStyle.prose)
                    .foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("From the \(source)")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}

/// Panel 10: the timeline, echoing the chronologies in many Unigrid brochures.
struct ChronologyPanel: View {
    let entries: [ChronologyEntry]

    var body: some View {
        UnigridPanel(title: GuidePanel.chronology.title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    UnigridChronologyRow(entry: entry)
                }
            }
        }
    }
}

/// Panel 11a: safety and regulations.
struct SafetyPanel: View {
    let safety: [String]
    let regulations: [String]

    var body: some View {
        UnigridPanel(title: GuidePanel.safetyAndRegulations.title) {
            VStack(alignment: .leading, spacing: 12) {
                GuideProseList(label: "Safety", items: safety)
                GuideProseList(label: "Regulations", items: regulations)
            }
        }
    }
}

/// The guide's actions, set as the last panel before the credits so a reader who has
/// scrolled the whole brochure does not have to scroll back for them.
struct GuideActionsPanel: View {
    let onCheckIn: () -> Void
    let onStamp: () -> Void
    let onAddToTrip: () -> Void
    let officialURL: URL?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onCheckIn) {
            Label("Check in", systemImage: "mappin.and.ellipse")
        }
        .buttonStyle(BrochureButtonStyle(.primary))
        Button(action: onStamp) {
            Label { Text("Stamp the passport") } icon: { StampIcon() }
        }
        .buttonStyle(BrochureButtonStyle(.secondary))
        Button(action: onAddToTrip) {
            Label("Add to a trip", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(BrochureButtonStyle(.secondary))
        if let officialURL {
            Link(destination: officialURL) {
                Label("nps.gov", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(BrochureButtonStyle(.secondary))
        }
    }
}

/// Panel 11b: credits, sources, photo credits and the non-affiliation line, across the
/// full width at the foot of the page, as they sit on the back of a brochure.
struct GuideCreditsPanel: View {
    @Environment(\.unigrid) private var style
    let credits: [String]
    let sources: [GuideSource]
    var photos: [GuideImage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(style.rule)
                .frame(height: 1)
            ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                Text(credit)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !photos.isEmpty {
                Text(photoLine)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sources) { source in
                if let url = source.url {
                    Link(source.title, destination: url)
                        .font(UnigridStyle.caption)
                } else {
                    Text(source.title)
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
            }
            NonAffiliationNotice()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var photoLine: String {
        let entries: [String] = photos.map { image in
            guard let caption = image.caption else { return image.credit }
            return "\(caption), \(image.credit)"
        }
        return "Photographs: \(entries.joined(separator: "; ")). "
            + "Photographs credited to the NPS are public domain."
    }
}

// MARK: - Shared pieces

struct GuideFieldLabel: View {
    @Environment(\.unigrid) private var style
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(UnigridStyle.dataLabel)
            .tracking(1)
            .foregroundStyle(style.inkSecondary)
    }
}

/// A label over a paragraph.
struct GuideNote: View {
    @Environment(\.unigrid) private var style
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GuideFieldLabel(label)
            Text(text)
                .font(UnigridStyle.prose)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dashed list, as the brochures set their practical information.
struct GuideLabelledList: View {
    @Environment(\.unigrid) private var style
    let label: String
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                GuideFieldLabel(label)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("— \(item)")
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Paragraphs under a label, for safety and regulations.
struct GuideProseList: View {
    @Environment(\.unigrid) private var style
    let label: String
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GuideFieldLabel(label)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A guide image with the credit it must carry (SPECIFICATION.md §6, §15).
struct GuideImagePanel: View {
    let image: GuideImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlacePhoto(image: image, aspectRatio: 3 / 2, maxPoints: 1000)
            PhotoCredit(image: image)
        }
    }
}
