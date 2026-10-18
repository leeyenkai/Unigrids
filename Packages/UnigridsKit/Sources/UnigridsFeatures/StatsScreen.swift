import Charts
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Stats (SPECIFICATION.md §11).
///
/// Everything here is computed on device from the log plus bundled reference data, in one
/// pass through `StatsReport`. Native design, not Unigrid — the brochure look belongs to
/// the guides.
public struct StatsScreen: View {
    @Environment(\.referenceStore) private var store

    @Query private var visits: [Visit]
    @Query private var hikes: [Hike]

    public init() {}

    private var report: StatsReport {
        StatsReport(
            places: store.places,
            visits: visits.map(\.summary),
            hikes: hikes.map(\.summary),
            trails: store.places.flatMap { store.trails(in: $0.id) },
            themes: store.themes
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                let report = report
                VStack(alignment: .leading, spacing: 28) {
                    completion(report)
                    coverage(report)
                    if !visits.isEmpty {
                        byYear(report)
                    }
                    if !visits.isEmpty {
                        bySeason(report)
                    }
                    themes(report)
                    trailTotals(report)
                    pending
                }
                .padding(20)
            }
            .navigationTitle("Stats")
            .overlay {
                if visits.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing logged yet", systemImage: "chart.bar")
                    } description: {
                        Text("Check in somewhere and your stats start here.")
                    }
                }
            }
        }
    }

    private func completion(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Completion and coverage")
            HStack(alignment: .center, spacing: 24) {
                CompletionRing(
                    completion: report.nationalParks,
                    caption: "National parks visited"
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("National parks")
                        .font(.headline)
                    Text(report.nationalParks.description)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if let nearest = report.nearestUnvisited {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nearest unvisited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(nearest.place.name)
                                .font(.subheadline.weight(.medium))
                            Text(
                                UnigridsFormat.distance(metres: nearest.distanceMetres)
                                    + " away"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func coverage(_ report: StatsReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(
                value: report.states.description,
                label: "States and territories",
                systemImage: "map"
            )
            StatTile(
                value: report.regions.description,
                label: "Passport regions",
                systemImage: "book.closed"
            )
            StatTile(
                value: "\(report.totalVisits)",
                label: "Visits logged",
                systemImage: "mappin.and.ellipse"
            )
            if let first = report.firstVisit {
                StatTile(
                    value: first.formatted(.dateTime.month(.abbreviated).year()),
                    label: "First visit",
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
    }

    private func byYear(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Visits by year")
            Chart(report.visitsByYear) { point in
                BarMark(
                    x: .value("Year", String(point.year)),
                    y: .value("Visits", point.count)
                )
                .foregroundStyle(UnigridStyle.parkGreen)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
            .accessibilityLabel("Visits by year")
            .accessibilityValue(
                report.visitsByYear
                    .map { "\($0.year): \($0.count)" }
                    .joined(separator: ", ")
            )
        }
    }

    private func bySeason(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Visits by season")
            Chart(report.visitsBySeason) { point in
                BarMark(
                    x: .value("Season", point.season.name),
                    y: .value("Visits", point.count)
                )
                .foregroundStyle(by: .value("Season", point.season.name))
                .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .frame(height: 160)
            .accessibilityLabel("Visits by season")
            .accessibilityValue(
                report.visitsBySeason
                    .map { "\($0.season.name): \($0.count)" }
                    .joined(separator: ", ")
            )
            // Weather per visit is captured when the visit is logged (§11) and needs
            // WeatherKit, which lands with the planner.
            Text("Weather stats arrive with WeatherKit in a later release.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func themes(_ report: StatsReport) -> some View {
        if !report.themeProgress.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading("Themes and landscapes")
                ForEach(report.themeProgress) { progress in
                    HStack(spacing: 12) {
                        Text(progress.theme.name)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(progress.completion.description)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress.completion.fraction)
                            .frame(width: 70)
                            .tint(UnigridStyle.parkGreen)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(progress.theme.name): \(progress.completion.description) visited"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func trailTotals(_ report: StatsReport) -> some View {
        if report.distanceHikedMetres > 0 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading("Trail and elevation")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                    spacing: 12
                ) {
                    StatTile(
                        value: UnigridsFormat.distance(metres: report.distanceHikedMetres),
                        label: "Distance hiked",
                        systemImage: "figure.walk"
                    )
                    StatTile(
                        value: UnigridsFormat.elevation(report.elevationGainedMetres),
                        label: "Elevation gained",
                        systemImage: "arrow.up.right"
                    )
                    StatTile(
                        value: UnigridsFormat.everests(
                            gainMetres: report.elevationGainedMetres
                        ),
                        label: "Everests climbed",
                        systemImage: "mountain.2"
                    )
                }
            }
        }
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Still to come", systemImage: "hourglass")
                .font(.subheadline.weight(.medium))
            Text(
                "A US map that fills in, weather and season stats per visit, share cards, "
                    + "and a year-in-review page."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SectionHeading: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}
