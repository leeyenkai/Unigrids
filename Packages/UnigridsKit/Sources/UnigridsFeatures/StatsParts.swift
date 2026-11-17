import Charts
import CoreLocation
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The pieces the Stats tab is drawn from (SPECIFICATION.md §11).

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

/// The share card itself: the band, the figure, and for each country the reader has
/// been to its grid of national parks and its map — a Japanese park on Japan's map, not
/// on the US one.
struct StatsShareCard: View {
    @Environment(\.unigrid) private var style
    let report: StatsReport
    let parks: [Place]
    let index: VisitIndex
    /// States, prefectures and counties visited, by country.
    let subdivisions: [Country: Set<String>]

    /// The countries with a national park visited; the first in the data if none is.
    private var countries: [StatsReport.CountryCompletion] {
        let visited = report.nationalParksByCountry.filter { $0.completion.visited > 0 }
        return visited.isEmpty ? Array(report.nationalParksByCountry.prefix(1)) : visited
    }

    private var detail: String {
        let shown = countries
        if shown.count > 1 {
            return "of \(report.nationalParks.total) · \(shown.count) countries"
        }
        guard let only = shown.first else { return "" }
        let regions = only.country == .unitedStates
            ? "\(report.states.visited) states"
            : "\(subdivisions[only.country]?.count ?? 0) "
            + only.country.subdivisionsTitle.lowercased()
        return "of \(only.completion.total) · \(regions)"
    }

    /// One country's own count, or every country's together.
    private func figure(_ shown: [StatsReport.CountryCompletion]) -> Int {
        shown.count == 1 ? shown[0].completion.visited : report.nationalParks.visited
    }

    var body: some View {
        let shown = countries
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("My national parks", kicker: "Unigrids")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(figure(shown))")
                        .font(.custom("HelveticaNeue-Bold", size: 64))
                        .foregroundStyle(style.ink)
                    Text(detail)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
                ForEach(shown) { figure in
                    VStack(alignment: .leading, spacing: 10) {
                        if shown.count > 1 {
                            Kicker("\(figure.country.name) · \(figure.completion.description)")
                        }
                        ParkGrid(
                            parks: parks.filter { $0.country == figure.country },
                            index: index,
                            side: shown.count > 1 ? 22 : 30
                        )
                        if figure.country == .unitedStates {
                            USTileMap(visited: Set(report.visitedStates.map(\.code)))
                        } else {
                            SubdivisionTileMap(
                                grid: .grid(for: figure.country),
                                visited: subdivisions[figure.country] ?? []
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(style.page)
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
