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
                    if let note = facts.elevationNote {
                        Text(note + ".")
                            .font(UnigridStyle.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
///
/// "Top" by what the data can say: trails that pass the guide's ranked sights first — the
/// walks to what the park is known for — then the longest.
struct TrailHighlightsPanel: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let trails: [Trail]
    /// Trails the guide names, which lead.
    var named: [UnigridsID] = []

    private var highlights: [Trail] {
        let leading = named.compactMap { id in trails.first { $0.id == id } }
        let rest = trails
            .filter { !named.contains($0.id) }
            .sorted {
                ($0.sightIDs.count, $0.lengthMetres) > ($1.sightIDs.count, $1.lengthMetres)
            }
        return Array((leading + rest).prefix(6))
    }

    var body: some View {
        UnigridPanel(title: GuidePanel.trailHighlights.title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights) { trail in
                    NavigationLink {
                        TrailDetailScreen(trail: trail)
                    } label: {
                        TrailRow(trail: trail)
                    }
                    .buttonStyle(.plain)
                    if trail.id != highlights.last?.id {
                        Hairline()
                    }
                }
                NavigationLink {
                    TrailCatalogueScreen(place: place)
                } label: {
                    Label(
                        "All \(trails.count) trails, "
                            + UnigridsFormat
                            .distance(metres: trails.reduce(0) { $0 + $1.lengthMetres }),
                        symbol: .list
                    )
                }
                .buttonStyle(BrochureButtonStyle(.secondary))
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
