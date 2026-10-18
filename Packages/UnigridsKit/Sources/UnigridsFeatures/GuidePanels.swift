import SwiftUI
import UnigridsCore
import UnigridsDesign

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
                    UnigridDataRow(label: "Established", value: String(year))
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
                        label: facts.annualVisitsYear.map { "Visits in \($0)" }
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

/// Panel 7: visitor centres, with a mark where a passport stamp lives.
struct VisitorCentresPanel: View {
    @Environment(\.unigrid) private var style
    let centres: [PointOfInterest]

    var body: some View {
        UnigridPanel(title: GuidePanel.visitorCentres.title) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(centres) { centre in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(centre.name)
                                .font(UnigridStyle.itemTitle)
                                .foregroundStyle(style.ink)
                            if centre.hasStamp {
                                StampIcon()
                                    .foregroundStyle(style.inkSecondary)
                                    .accessibilityLabel("Has a passport stamp")
                            }
                        }
                        if let summary = centre.summary {
                            Text(summary)
                                .font(UnigridStyle.prose)
                                .foregroundStyle(style.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let hours = centre.hours {
                            Text(hours)
                                .font(UnigridStyle.caption)
                                .foregroundStyle(style.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// Panel 9: entrances, reservations, permits, camping, lodging and closures.
struct PlanYourVisitPanel: View {
    @Environment(\.unigrid) private var style
    let plan: PlanYourVisit

    var body: some View {
        UnigridPanel(title: GuidePanel.planYourVisit.title) {
            VStack(alignment: .leading, spacing: 14) {
                GuideLabelledList(label: "Entrances", items: plan.entrances)
                if let reservations = plan.reservations {
                    VStack(alignment: .leading, spacing: 4) {
                        GuideFieldLabel("Reservations")
                        Text(reservations)
                            .font(UnigridStyle.prose)
                            .foregroundStyle(style.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                GuideLabelledList(label: "Permits", items: plan.permits)
                GuideLabelledList(label: "Camping", items: plan.camping)
                GuideLabelledList(label: "Lodging", items: plan.lodging)
                GuideLabelledList(label: "Seasonal closures", items: plan.seasonalClosures)
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

/// Panel 11b: credits, sources and the non-affiliation line, across the full width at the
/// foot of the page, as they sit on the back of a brochure.
struct GuideCreditsPanel: View {
    @Environment(\.unigrid) private var style
    let credits: [String]
    let sources: [GuideSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(style.rule)
                .frame(height: 1)
            ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                Text(credit)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
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
    @Environment(\.unigrid) private var style
    let image: GuideImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .frame(maxWidth: .infinity)
                .clipped()
            if let caption = image.caption {
                Text(caption)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
            Text(image.credit)
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let assetName = image.assetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else if let url = image.url {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary).frame(height: 180)
                }
            }
        } else {
            Rectangle().fill(.quaternary).frame(height: 180)
        }
    }
}
