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
                    Text("of \(report.nationalParks.total) · \(report.states.visited) states")
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
