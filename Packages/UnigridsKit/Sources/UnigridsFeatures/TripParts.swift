import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// A trip's map, its legs and what each stop has posted (SPECIFICATION.md §10).

/// The trip's stops on a map, numbered, joined in order by a straight rule.
struct TripMap: View {
    @Environment(\.unigrid) private var style
    let places: [Place]
    /// Roads MapKit routed between stops. Where a leg has none, the straight rule stands.
    var roads: [[Coordinate]] = []

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if places.count > 1, roads.count < places.count - 1 {
                MapPolyline(coordinates: places.map(\.centre.clCoordinate))
                    .stroke(style.ink.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(roads.enumerated()), id: \.offset) { _, road in
                MapPolyline(coordinates: road.map(\.clCoordinate))
                    .stroke(
                        style.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                Annotation(place.name, coordinate: place.centre.clCoordinate) {
                    SightNumber(number: index + 1)
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            emphasis: .muted,
            pointsOfInterest: .excludingAll
        ))
        .onAppear { frameStops(animated: false) }
        .onChange(of: places.map(\.id)) { frameStops(animated: true) }
    }

    /// Fit every stop, refitting as stops are added, removed or reordered. A single stop
    /// gets a regional view rather than a street-level one.
    private func frameStops(animated: Bool) {
        guard let box = BoundingBox.enclosing(places.map(\.centre))?.expanded(by: 0.25) else {
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

/// The drive into a stop: MapKit's time and road distance, or the straight line where
/// it could not route one.
struct LegLine: View {
    @Environment(\.unigrid) private var style
    let leg: RoutedLeg?
    let failed: Bool
    let straightLine: Double

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(style.rule)
                .frame(width: 2, height: 16)
                .padding(.leading, 10)
                .padding(.trailing, 12)
            if let leg {
                Label(
                    UnigridsFormat.duration(leg.seconds) + " · "
                        + UnigridsFormat.distance(metres: leg.metres),
                    systemImage: "car"
                )
            } else if failed {
                Label(
                    "No road route · "
                        + UnigridsFormat.distance(metres: straightLine) + " straight line",
                    systemImage: "airplane"
                )
            } else {
                Label("Routing…", systemImage: "car")
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
