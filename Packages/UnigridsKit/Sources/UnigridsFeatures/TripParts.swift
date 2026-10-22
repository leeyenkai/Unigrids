import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// A trip's map, its legs and what each stop has posted (SPECIFICATION.md §10).

/// The trip's stops on a map, numbered, joined in order by the roads MapKit routed or,
/// where it routed none, a dashed straight rule.
struct TripMap: View {
    @Environment(\.unigrid) private var style
    let stops: [ResolvedStop]
    /// Roads MapKit routed between stops. Where a leg has none, the straight rule stands.
    var roads: [[Coordinate]] = []

    @State private var position: MapCameraPosition = .automatic

    /// A stop with somewhere to draw it, numbered as the itinerary numbers it.
    private struct Point {
        let index: Int
        let stop: ResolvedStop
        let coordinate: Coordinate
    }

    private var points: [Point] {
        stops.enumerated().compactMap { index, stop in
            stop.coordinate.map { Point(index: index, stop: stop, coordinate: $0) }
        }
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if points.count > 1, roads.count < points.count - 1 {
                MapPolyline(coordinates: points.map(\.coordinate.clCoordinate))
                    .stroke(style.ink.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(roads.enumerated()), id: \.offset) { _, road in
                MapPolyline(coordinates: road.map(\.clCoordinate))
                    .stroke(
                        style.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(points, id: \.stop.id) { point in
                Annotation(point.stop.title, coordinate: point.coordinate.clCoordinate) {
                    StopMarker(number: point.index + 1, stop: point.stop)
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            emphasis: .muted,
            pointsOfInterest: .excludingAll
        ))
        .onAppear { frameStops(animated: false) }
        .onChange(of: stops.map(\.routeKey)) { frameStops(animated: true) }
        .accessibilityLabel("Map of the trip's \(stops.count) stops")
    }

    /// Fit every stop, refitting as stops are added, removed or reordered. A single stop
    /// gets a regional view rather than a street-level one.
    private func frameStops(animated: Bool) {
        guard let box = BoundingBox.enclosing(points.map(\.coordinate))?.expanded(by: 0.25) else {
            return
        }
        let region = MKCoordinateRegion(
            center: box.centre.clCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(box.north - box.south, 1.5),
                longitudeDelta: max(box.east - box.west, 1.5)
            )
        )
        if animated {
            withAnimation { position = .region(region) }
        } else {
            position = .region(region)
        }
    }
}

/// A stop on the trip map: its number, square for a place and round for anything inside
/// or near one, so the parks read as the trip's spine.
private struct StopMarker: View {
    let number: Int
    let stop: ResolvedStop

    var body: some View {
        if case .place = stop.stop.target {
            SightNumber(number: number)
        } else {
            SightNumber(number: number)
                .clipShape(Circle())
        }
    }
}

/// The drive into a stop: MapKit's time and road distance, or the straight line where
/// it could not route one, with a way to try again.
struct LegLine: View {
    @Environment(\.unigrid) private var style
    let leg: RoutedLeg?
    let failed: Bool
    let straightLine: Double
    /// Two stops at the same point — a park and its own visitor centre, say.
    var sameSpot = false
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(style.rule)
                .frame(width: 2, height: 16)
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .accessibilityHidden(true)
            if sameSpot {
                Text("Same place")
                    .foregroundStyle(style.inkSecondary)
            } else if let leg {
                Label(
                    UnigridsFormat.duration(leg.seconds) + " · "
                        + UnigridsFormat.distance(metres: leg.metres),
                    systemImage: UnigridsSymbol.directions.systemName
                )
                .accessibilityLabel(
                    "Drive, \(UnigridsFormat.duration(leg.seconds)), "
                        + UnigridsFormat.distance(metres: leg.metres)
                )
            } else if failed {
                Text(
                    "No road route found · "
                        + UnigridsFormat.distance(metres: straightLine) + " straight line"
                )
                if let onRetry {
                    Button("Retry", action: onRetry)
                        .font(UnigridStyle.dataLabel)
                        .buttonStyle(.borderless)
                }
            } else {
                Text("Routing…")
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .font(UnigridStyle.rowDetail)
        .foregroundStyle(style.ink)
        .accessibilityElement(children: .combine)
    }
}

/// A stop's forecast and flags.
struct StopExtras: View {
    let weather: DailyWeather?
    let flags: [StopFlag]

    var body: some View {
        if weather != nil || !flags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let weather {
                    ForecastLine(weather: weather)
                }
                if !flags.isEmpty {
                    StopFlagList(flags: flags)
                }
            }
        }
    }
}

/// One stop: its number, what it is, the day, and whether it has been visited on this
/// trip. The row opens the stop's place; the trailing control opens its day, time and
/// notes.
struct StopRow: View {
    @Environment(\.unigrid) private var style
    let number: Int
    let entry: ResolvedStop
    let trip: Trip
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SightNumber(number: number, isSelected: visited)
            Group {
                if let place = entry.place {
                    NavigationLink(value: place.id) { label }
                } else {
                    label
                }
            }
            Button(action: onDetails) {
                Image(.details)
                    .imageScale(.large)
                    .foregroundStyle(style.ink)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Day, time and notes for \(entry.title)")
        }
        .contextMenu {
            Button(action: onDetails) {
                Label("Day, time and notes", symbol: .details)
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if entry.stop.target != .place {
                    Image(entry.symbol)
                        .imageScale(.small)
                        .foregroundStyle(style.inkSecondary)
                        .accessibilityHidden(true)
                }
                Text(entry.title)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
            }
            Text(detail)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
            if !entry.stop.notes.isEmpty {
                Text(entry.stop.notes)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visited: Bool {
        (trip.visits ?? []).contains { $0.place == entry.stop.place }
    }

    private var detail: String {
        var parts = [entry.subtitle]
        if let day = entry.stop.plannedDate {
            let calendar = UnigridsCalendar.gregorian(at: entry.place)
            parts.append(
                entry.stop.isTimed
                    ? day.formatted(UnigridsFormat.moment(in: calendar))
                    : day.formatted(UnigridsFormat.weekday(in: calendar))
            )
        }
        if visited {
            parts.append("Visited")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
