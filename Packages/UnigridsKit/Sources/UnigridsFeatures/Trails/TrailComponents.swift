import Charts
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// A trail's elevation along its length, as a filled profile (SPECIFICATION.md §8).
struct TrailProfileChart: View {
    @Environment(\.unigrid) private var style
    let trail: Trail
    var height: CGFloat = 120
    var showsAxes = true

    var body: some View {
        if trail.profile.count >= 2 {
            let low = trail.profile.map(\.elevationMetres).min() ?? 0
            let high = trail.profile.map(\.elevationMetres).max() ?? 0
            let pad = max((high - low) * 0.15, 10)
            Chart(trail.profile, id: \.distanceMetres) { point in
                AreaMark(
                    x: .value("Distance", point.distanceMetres / 1000),
                    yStart: .value("Floor", low - pad),
                    yEnd: .value("Elevation", point.elevationMetres)
                )
                .foregroundStyle(style.trail.opacity(0.22))
                LineMark(
                    x: .value("Distance", point.distanceMetres / 1000),
                    y: .value("Elevation", point.elevationMetres)
                )
                .foregroundStyle(style.trail)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: (low - pad) ... (high + pad))
            .chartXAxis(showsAxes ? .automatic : .hidden)
            .chartYAxis(showsAxes ? .automatic : .hidden)
            .chartXAxisLabel(showsAxes ? "km" : "", alignment: .trailing)
            .frame(height: height)
            .accessibilityLabel("Elevation profile")
            .accessibilityValue(
                "From \(UnigridsFormat.elevation(trail.profile.first?.elevationMetres ?? 0)) "
                    + "to \(UnigridsFormat.elevation(trail.profile.last?.elevationMetres ?? 0)), "
                    + "highest \(UnigridsFormat.elevation(high))"
            )
        }
    }
}

/// The figures every trail view leads with: length, climb, the estimated effort.
struct TrailFigures: View {
    let trail: Trail

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            FigureBlock(
                value: UnigridsFormat.distance(metres: trail.walkedMetres),
                label: trail.isLoop ? "Loop" : "There and back",
                compact: true
            )
            if let climb = trail.climbMetres {
                FigureBlock(
                    value: UnigridsFormat.elevation(climb),
                    label: "Climb",
                    compact: true
                )
            }
            if !trail.isLoop {
                FigureBlock(
                    value: UnigridsFormat.distance(metres: trail.lengthMetres),
                    label: "One way, as mapped",
                    compact: true
                )
            }
            if let high = trail.highPointMetres {
                FigureBlock(
                    value: UnigridsFormat.elevation(high),
                    label: "High point",
                    compact: true
                )
            }
            FigureBlock(
                value: UnigridsFormat.duration(trail.estimatedDuration),
                label: "Walking time, est.",
                compact: true
            )
        }
    }
}

/// A trail in a list: name, length, climb and the effort band, with a tick once hiked.
struct TrailRow: View {
    @Environment(\.unigrid) private var style
    let trail: Trail
    var parkName: String?
    var hiked = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DifficultyMark(difficulty: trail.estimatedDifficulty)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(trail.name)
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                        .lineLimit(2)
                    if hiked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(style.accent)
                            .accessibilityLabel("Hiked")
                    }
                }
                Text(detail)
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [
            UnigridsFormat
                .distance(metres: trail.walkedMetres) + (trail.isLoop ? " loop" : " return"),
        ]
        if let climb = trail.climbMetres {
            parts.append("↑ " + UnigridsFormat.elevation(climb))
        }
        if let difficulty = trail.estimatedDifficulty {
            parts.append(difficulty.name)
        }
        if let parkName {
            parts.append(parkName)
        }
        return parts.joined(separator: " · ")
    }
}

/// The effort band as a small square that fills as the trail gets harder — the
/// brochure's way of grading without a colour code.
struct DifficultyMark: View {
    @Environment(\.unigrid) private var style
    let difficulty: TrailDifficulty?

    var body: some View {
        let level = difficulty.flatMap { TrailDifficulty.allCases.firstIndex(of: $0) }
        VStack(spacing: 1.5) {
            ForEach((0 ..< 5).reversed(), id: \.self) { step in
                Rectangle()
                    .fill(level.map { step <= $0 } == true ? style.trail : style.rule)
                    .frame(width: 14, height: 3)
            }
        }
        .frame(width: 18)
        .accessibilityLabel(difficulty.map { "Effort: \($0.name)" } ?? "Effort not measured")
    }
}

/// A trail's card in the explorer and its page in the catalogue share these actions.
struct TrailActions: View {
    @Environment(\.modelContext) private var context
    let trail: Trail
    @Query private var hikes: [Hike]
    @State private var completion = HikeCompletion.full
    @State private var showConfirm = false
    @State private var saved = false

    private var hikedDates: [Date] {
        hikes.filter { $0.trailID == trail.id.rawValue }.map(\.date).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let last = hikedDates.first {
                Label(
                    "Hiked \(hikedDates.count == 1 ? "" : "\(hikedDates.count) times, last ")"
                        + last.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "checkmark.circle.fill"
                )
                .font(UnigridStyle.rowDetail)
            }
            Button {
                showConfirm = true
            } label: {
                Label(saved ? "Logged" : "Mark as hiked", systemImage: "figure.hiking")
            }
            .buttonStyle(BrochureButtonStyle(.primary))
            .confirmationDialog("Log this hike", isPresented: $showConfirm) {
                Button("Hiked it all") { log(.full) }
                Button("Part of the way") { log(.partial) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(trail.name), today. It joins your visit to the park.")
            }
        }
    }

    private func log(_ completion: HikeCompletion) {
        do {
            try LogStore(context: context).markHiked(
                trail.id, in: trail.placeID, completion: completion
            )
            saved = true
        } catch {
            saved = false
        }
    }
}
