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
                label: walkedLabel,
                compact: true
            )
            if let climb = trail.climbMetres {
                FigureBlock(
                    value: UnigridsFormat.elevation(climb),
                    label: "Climb",
                    compact: true
                )
            }
            if isWalkedTwice {
                FigureBlock(
                    value: UnigridsFormat.distance(metres: trail.lengthMetres),
                    label: "One way",
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

    /// A trail mapped one way is walked there and back; a loop, or a trail that ends
    /// somewhere else, once.
    private var isWalkedTwice: Bool {
        trail.routeType == .outAndBack || trail.routeType == nil
    }

    private var walkedLabel: String {
        switch trail.routeType {
        case .loop: "Loop"
        case .pointToPoint: "One way"
        case .outAndBack, nil: "There and back"
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
                        Image(.visited)
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
        let walked = UnigridsFormat.distance(metres: trail.walkedMetres)
        let length = switch trail.routeType {
        case .loop: walked + " loop"
        case .pointToPoint: walked + " one way"
        case .outAndBack, nil: walked + " there and back"
        }
        var parts = [length]
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

/// A trail's card in the explorer and its page in the catalogue share these actions: log
/// a hike, add the trail to a trip, and the hikes already logged on it, each of which can
/// be deleted.
struct TrailActions: View {
    @Environment(\.modelContext) private var context
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let trail: Trail
    @Query private var hikes: [Hike]
    @State private var logging = false
    @State private var addingToTrip = false
    @State private var error: String?

    init(trail: Trail) {
        self.trail = trail
        let id = trail.id.rawValue
        _hikes = Query(filter: #Predicate<Hike> { $0.trailID == id }, sort: \.date, order: .reverse)
    }

    private var place: Place? {
        store.place(trail.placeID)
    }

    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button {
                    logging = true
                } label: {
                    Label("Mark as hiked", symbol: .hike)
                }
                .buttonStyle(BrochureButtonStyle(.primary))
                if place != nil {
                    Button {
                        addingToTrip = true
                    } label: {
                        Label("Add to trip", symbol: .addToTrip)
                    }
                    .buttonStyle(BrochureButtonStyle(.secondary))
                }
            }
            if !hikes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(hikes.count == 1 ? "Hiked once" : "Hiked \(hikes.count) times")
                    ForEach(hikes.prefix(5)) { hike in
                        HikeLine(hike: hike, calendar: calendar) { delete(hike) }
                    }
                    if hikes.count > 5 {
                        Text("And \(hikes.count - 5) more, on the visits in Trips.")
                            .font(UnigridStyle.caption)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
            if let error {
                ErrorLine(error)
            }
        }
        .unigridsSheet(isPresented: $logging) {
            HikeSheet(trail: trail)
        }
        .unigridsSheet(isPresented: $addingToTrip) {
            if let place {
                AddToTripSheet(place: place, target: .trail(trail.id), stopName: trail.name)
            }
        }
    }

    private func delete(_ hike: Hike) {
        do {
            let change = try LogStore(context: context).delete(hike: hike)
            undo?.offer(change, message: "Hike on \(trail.name) deleted")
            error = nil
        } catch {
            self.error = "That hike could not be deleted: \(error.localizedDescription)"
        }
    }
}

/// One logged hike: its day and how far, and a way to delete it.
private struct HikeLine: View {
    @Environment(\.unigrid) private var style
    let hike: Hike
    let calendar: Calendar
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(.visited)
                .foregroundStyle(style.accent)
                .accessibilityHidden(true)
            Text(hike.date, format: UnigridsFormat.day(in: calendar))
                .foregroundStyle(style.ink)
            Text(hike.completion.name)
                .foregroundStyle(style.inkSecondary)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Image(.delete)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(style.inkSecondary)
            .accessibilityLabel("Delete this hike")
        }
        .font(UnigridStyle.rowDetail)
        .accessibilityElement(children: .combine)
    }
}

/// Log a hike: which day, and whether it went the whole way. It joins the visit to the
/// park that day, or starts one (SPECIFICATION.md §8, §9).
struct HikeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let trail: Trail

    @State private var day = Date()
    @State private var completion = HikeCompletion.full
    @State private var error: String?

    private var place: Place? {
        store.place(trail.placeID)
    }

    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

    var body: some View {
        SheetPage(
            "Mark as hiked",
            kicker: trail.name,
            actions: .confirm("Log hike", cancel: { dismiss() }, action: save),
            height: 440
        ) {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, calendar.timeZone)
                    Picker("How far", selection: $completion) {
                        ForEach(HikeCompletion.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    FormNote(
                        "It joins that day's visit to \(place?.name ?? "the park"), or starts one."
                    )
                }
                if let error {
                    Section { ErrorLine(error) }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func save() {
        // Today is logged at this moment; another day at noon there, so it reads as that
        // day wherever it is read.
        let today = UnigridsCalendar.isSameDay(day, Date(), calendar: calendar)
        let date = today ? Date() : UnigridsCalendar.noon(
            onDayOf: day,
            shownIn: calendar,
            in: calendar
        )
        do {
            let log = LogStore(context: context)
            let madeVisit = try log.visit(to: trail.placeID, on: date, calendar: calendar) == nil
            let hike = try log.markHiked(
                trail.id, in: trail.placeID, on: date, completion: completion, calendar: calendar
            )
            undo?.offer(
                log.undoing(hike: hike, madeVisit: madeVisit),
                message: "Hike on \(trail.name) logged"
            )
            dismiss()
        } catch {
            self.error = "This hike could not be saved: \(error.localizedDescription)"
        }
    }
}
