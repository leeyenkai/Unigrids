import Charts
import CoreLocation
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Stats (SPECIFICATION.md §11).
///
/// Everything here is computed on device from the log plus bundled reference data, in one
/// pass through `StatsReport`, and drawn in the same squares and rules as the rest of the
/// app: the national parks as a grid that fills in, the states as a tile map that fills in.
public struct StatsScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style

    @Query private var visits: [Visit]
    @Query private var hikes: [Hike]
    @Query private var trips: [Trip]

    @State private var origin: Coordinate?
    @State private var locating = false
    @State private var locator = OnSiteCheck()

    public init() {}

    private var report: StatsReport {
        StatsReport(
            places: store.places,
            visits: store.placeDaySummaries(visits),
            hikes: store.placeDaySummaries(hikes),
            trails: store.allTrails,
            themes: store.themes,
            origin: origin
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                let report = report
                VStack(alignment: .leading, spacing: 0) {
                    BandHeader(
                        "Stats",
                        kicker: "\(report.totalVisits) "
                            + (report.totalVisits == 1 ? "visit" : "visits") + " logged"
                    )
                    VStack(alignment: .leading, spacing: 32) {
                        nationalParks(report)
                        if !visits.isEmpty {
                            ShareCardButton(
                                title: "My national parks",
                                label: "Share my parks",
                                weight: .primary
                            ) {
                                StatsShareCard(
                                    report: report,
                                    parks: store.nationalParks,
                                    index: VisitIndex(visits: visits, trips: trips)
                                )
                            }
                            NavigationLink {
                                YearInReviewScreen()
                            } label: {
                                Label("Year in review", symbol: .yearInReview)
                            }
                            .buttonStyle(BrochureButtonStyle(.secondary))
                        }
                        ShareableSection("States and territories") { statesSection(report) }
                        ShareableSection("Figures") { figures(report) }
                        if !visits.isEmpty {
                            ShareableSection("In a row") {
                                StreaksSection(visits: store.placeDaySummaries(visits))
                            }
                        }
                        ShareableSection("Kinds of place") { KindsOfPlaceSection(visits: visits) }
                        if !visits.isEmpty {
                            ShareableSection("Visits by year") { byYear(report) }
                            ShareableSection("Visits by month") {
                                VisitsByMonthSection(visits: visits)
                            }
                            ShareableSection("Visits by season") { bySeason(report) }
                        }
                        WeatherStatsSection(visits: visits)
                        themes(report)
                        trailTotals(report)
                        // Not shareable: it says where the reader is.
                        nearest(report)
                    }
                    .padding(UnigridStyle.pageMargin)
                    .padding(.top, 8)
                }
            }
            .background(style.page)
            .navigationDestination(for: UnigridsID.self) { id in
                PlaceDestination(placeID: id)
            }
            .navigationTitle("Stats")
            .toolbarTitleDisplayMode(.inline)
            #if os(iOS)
                .toolbar { SettingsToolbarItem() }
            #endif
        }
    }

    private func statesSection(_ report: StatsReport) -> some View {
        SubdivisionMapsSection(report: report, visits: visits)
    }

    private func figures(_ report: StatsReport) -> some View {
        let visited = Set(visits.map(\.place)).compactMap(store.place)
        // By kind, not tier: Japan's quasi-national parks share the state parks' tier and
        // circle, but they are not state parks.
        let quasi = visited.count { $0.kind == .quasiNationalPark }
        let landscapes = visited.count {
            $0.kind == .protectedLandscape || $0.kind == .natureReserve
        }
        return FigureGrid(minimum: 140, spacing: 16) {
            FigureBlock(value: "\(visited.count { $0.tier == .npsUnit })", label: "Other NPS sites")
            FigureBlock(value: "\(visited.count { $0.kind == .statePark })", label: "State parks")
            if quasi > 0 {
                FigureBlock(value: "\(quasi)", label: "Quasi-national parks")
            }
            if landscapes > 0 {
                FigureBlock(value: "\(landscapes)", label: "Landscapes and reserves")
            }
            if report.regionsByCountry.count > 1 {
                FigureBlock(value: report.countries.description, label: "Countries")
                ForEach(report.regionsByCountry) { figure in
                    FigureBlock(
                        value: figure.completion.description,
                        label: "Passport regions, \(figure.country.name)"
                    )
                }
            } else {
                FigureBlock(value: report.regions.description, label: "Passport regions")
            }
            FigureBlock(value: "\(report.totalVisits)", label: "Visits logged")
            if let first = report.firstVisit {
                FigureBlock(
                    value: first.formatted(UnigridsFormat.month()),
                    label: "First visit"
                )
            }
            if let latest = report.latestVisit {
                FigureBlock(
                    value: latest.formatted(UnigridsFormat.month()),
                    label: "Latest visit"
                )
            }
        }
    }

    private func byYear(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("Visits by year")
            Chart(report.visitsByYear) { point in
                BarMark(
                    x: .value("Year", String(point.year)),
                    y: .value("Visits", point.count),
                    width: .ratio(0.6)
                )
                .foregroundStyle(style.ink)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .frame(height: 180)
            .graphicTypeSize()
            .accessibilityLabel("Visits by year")
            .accessibilityValue(
                report.visitsByYear.map { "\($0.year): \($0.count)" }.joined(separator: ", ")
            )
        }
    }

    private func bySeason(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("Visits by season")
            Chart(report.visitsBySeason) { point in
                BarMark(
                    x: .value("Season", point.season.name),
                    y: .value("Visits", point.count),
                    width: .ratio(0.6)
                )
                .foregroundStyle(style.accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .frame(height: 150)
            .graphicTypeSize()
            .accessibilityLabel("Visits by season")
            .accessibilityValue(
                report.visitsBySeason.map { "\($0.season.name): \($0.count)" }
                    .joined(separator: ", ")
            )
        }
    }

    @ViewBuilder
    private func themes(_ report: StatsReport) -> some View {
        if !report.themeProgress.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHead("Themes and landscapes", detail: "national parks seen")
                ForEach(report.themeProgress) { progress in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(progress.theme.name)
                                .font(UnigridStyle.rowTitle)
                                .foregroundStyle(style.ink)
                            Spacer()
                            Text(progress.completion.description)
                                .font(UnigridStyle.dataLabel)
                                .monospacedDigit()
                                .foregroundStyle(style.inkSecondary)
                        }
                        SquareBar(
                            fraction: progress.completion.fraction,
                            segments: progress.completion.total
                        )
                    }
                    .accessibilityElement(children: .ignore)
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
            VStack(alignment: .leading, spacing: 12) {
                SectionHead("Trail and elevation")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                    spacing: 16
                ) {
                    FigureBlock(
                        value: UnigridsFormat.distance(metres: report.distanceHikedMetres),
                        label: "Distance hiked"
                    )
                    FigureBlock(
                        value: UnigridsFormat.elevation(report.elevationGainedMetres),
                        label: "Elevation gained"
                    )
                    FigureBlock(
                        value: UnigridsFormat.everests(gainMetres: report.elevationGainedMetres),
                        label: "Everests climbed"
                    )
                    FigureBlock(
                        value: UnigridsFormat.distance(metres: report.longestHikeMetres),
                        label: "Longest hike"
                    )
                    if let high = report.highestPointMetres {
                        FigureBlock(value: UnigridsFormat.elevation(high), label: "Highest point")
                    }
                    FigureBlock(
                        value: "\(Set(hikes.map(\.trailID)).count)",
                        label: "Trails hiked"
                    )
                }
            }
        }
    }

    private func nearest(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("Nearest unvisited national park")
            if let nearest = report.nearestUnvisited {
                NavigationLink(value: nearest.place.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nearest.place.name)
                                .font(UnigridStyle.figureSmall)
                                .foregroundStyle(style.ink)
                            Text(
                                UnigridsFormat.distance(metres: nearest.distanceMetres)
                                    + " away, as the crow flies · "
                                    + nearest.place.bandLine
                            )
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                        }
                        Spacer()
                        Image(.next)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    locating = true
                    Task {
                        origin = await locator.currentCoordinate()
                        locating = false
                    }
                } label: {
                    Label(locating ? "Finding you…" : "Use my location", symbol: .locate)
                }
                .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
                .disabled(locating)
                Text("Your location is used once, on this device, and not kept.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}

extension StatsScreen {
    private func nationalParks(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("National parks", detail: report.nationalParks.description)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(report.nationalParks.visited)")
                    .font(.custom("HelveticaNeue-Bold", size: 56, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(style.ink)
                Text("of \(report.nationalParks.total) visited")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            if report.nationalParksByCountry.count > 1 {
                NationalParksByCountry(
                    figures: report.nationalParksByCountry,
                    index: VisitIndex(visits: visits, trips: trips)
                )
            } else {
                ParkGrid(
                    parks: store.nationalParks,
                    index: VisitIndex(visits: visits, trips: trips),
                    side: 26
                )
            }
            if visits.isEmpty {
                Text("Check in or stamp the passport anywhere, and the squares start to fill.")
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}
