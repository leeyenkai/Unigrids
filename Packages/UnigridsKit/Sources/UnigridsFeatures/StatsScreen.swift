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
            visits: visits.map(\.summary),
            hikes: hikes.map(\.summary),
            trails: store.places.flatMap { store.trails(in: $0.id) },
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
                        statesSection(report)
                        figures(report)
                        if !visits.isEmpty {
                            byYear(report)
                            bySeason(report)
                        }
                        themes(report)
                        trailTotals(report)
                        nearest(report)
                        if !visits.isEmpty {
                            ShareStatsButton(
                                report: report,
                                index: VisitIndex(visits: visits, trips: trips)
                            )
                        }
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
        }
    }

    private func nationalParks(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("National parks", detail: report.nationalParks.description)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(report.nationalParks.visited)")
                    .font(.custom("HelveticaNeue-Bold", size: 56, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(style.ink)
                Text("of 63 visited")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            ParkGrid(
                parks: store.nationalParks,
                index: VisitIndex(visits: visits, trips: trips),
                side: 26
            )
            if visits.isEmpty {
                Text("Check in or stamp the passport anywhere, and the squares start to fill.")
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }

    private func statesSection(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("States and territories", detail: report.states.description)
            USTileMap(visited: Set(report.visitedStates.map(\.code)))
        }
    }

    private func figures(_ report: StatsReport) -> some View {
        let byTier = Dictionary(
            grouping: Set(visits.map(\.place)).compactMap(store.place),
            by: \.tier
        )
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 18
        ) {
            FigureBlock(value: "\(byTier[.npsUnit]?.count ?? 0)", label: "Other NPS sites")
            FigureBlock(value: "\(byTier[.statePark]?.count ?? 0)", label: "State parks")
            FigureBlock(value: report.regions.description, label: "Passport regions")
            FigureBlock(value: "\(report.totalVisits)", label: "Visits logged")
            if let first = report.firstVisit {
                FigureBlock(
                    value: first.formatted(.dateTime.month(.abbreviated).year()),
                    label: "First visit"
                )
            }
            if let latest = report.latestVisit {
                FigureBlock(
                    value: latest.formatted(.dateTime.month(.abbreviated).year()),
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
                                    + nearest.place.statesDescription
                            )
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
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
                    Label(locating ? "Finding you…" : "Use my location", systemImage: "location")
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

/// A completion bar cut into one square per item, so "4 of 6" reads as six squares with
/// four filled rather than as a percentage.
struct SquareBar: View {
    @Environment(\.unigrid) private var style
    let fraction: Double
    let segments: Int

    var body: some View {
        let filled = Int((fraction * Double(segments)).rounded())
        HStack(spacing: 2) {
            ForEach(0 ..< max(segments, 1), id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? style.accent : style.rule)
                    .frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The states and territories as equal squares, filled where the reader has been.
struct USTileMap: View {
    @Environment(\.unigrid) private var style
    let visited: Set<String>

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let side = min(
                (proxy.size.width - gap * CGFloat(USTileGrid.columns - 1)) /
                    CGFloat(USTileGrid.columns),
                44
            )
            ZStack(alignment: .topLeading) {
                ForEach(USTileGrid.tiles, id: \.code) { tile in
                    StateTile(code: tile.code, side: side, isVisited: visited.contains(tile.code))
                        .offset(
                            x: offsetX(tile, side: side, gap: gap),
                            y: offsetY(tile, side: side, gap: gap)
                        )
                }
            }
        }
        .aspectRatio(
            CGFloat(USTileGrid.columns) / (CGFloat(USTileGrid.rows) + 0.4),
            contentMode: .fit
        )
        .frame(maxWidth: 520)
    }
}

extension USTileMap {
    func offsetX(_ tile: USTileGrid.Tile, side: CGFloat, gap: CGFloat) -> CGFloat {
        CGFloat(tile.column) * (side + gap)
    }

    /// The territories' row sits a little apart from the states'.
    func offsetY(_ tile: USTileGrid.Tile, side: CGFloat, gap: CGFloat) -> CGFloat {
        let apart: CGFloat = tile.row == USTileGrid.rows - 1 ? side * 0.4 : 0
        return CGFloat(tile.row) * (side + gap) + apart
    }
}

/// One state's square.
struct StateTile: View {
    @Environment(\.unigrid) private var style
    let code: String
    let side: CGFloat
    let isVisited: Bool

    var body: some View {
        Text(code)
            .font(.custom("HelveticaNeue-Bold", size: max(side * 0.3, 8)))
            .foregroundStyle(isVisited ? style.onAccent : style.inkSecondary)
            .frame(width: side, height: side)
            .background(isVisited ? style.accent : Color.clear)
            .overlay {
                Rectangle().strokeBorder(isVisited ? style.accent : style.rule, lineWidth: 1)
            }
            .accessibilityLabel(
                "\(USState.named(code)?.name ?? code), \(isVisited ? "visited" : "not visited")"
            )
    }
}

/// Share the stats as an image card (SPECIFICATION.md §11, "every stat card can become a
/// share card"): rendered on device, handed to the share sheet, never uploaded by Unigrids.
struct ShareStatsButton: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let report: StatsReport
    let index: VisitIndex

    var body: some View {
        if let image = rendered {
            ShareLink(
                item: image,
                preview: SharePreview("My national parks", image: image)
            ) {
                Label("Share my parks", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(BrochureButtonStyle(.primary))
        }
    }

    @MainActor
    private var rendered: Image? {
        let card = StatsShareCard(report: report, parks: store.nationalParks, index: index)
            .environment(\.unigrid, style)
            .frame(width: 540)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.cgImage.map { Image(decorative: $0, scale: 2) }
    }
}

/// The share card itself: the band, the figure, the grid, the states.
struct StatsShareCard: View {
    @Environment(\.unigrid) private var style
    let report: StatsReport
    let parks: [Place]
    let index: VisitIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("My national parks", kicker: "Unigrids")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(report.nationalParks.visited)")
                        .font(.custom("HelveticaNeue-Bold", size: 64))
                        .foregroundStyle(style.ink)
                    Text("of 63 · \(report.states.visited) states")
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
                ParkGrid(parks: parks, index: index, side: 30)
                USTileMap(visited: Set(report.visitedStates.map(\.code)))
            }
            .padding(20)
        }
        .background(style.page)
    }
}
