import MapKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// Panel 5: the park drawn — its outline, numbered sights and visitor centres — with the
/// way into the 3D explorer.
struct ParkMapPanel: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let place: Place
    let sights: [PointOfInterest]
    let centres: [PointOfInterest]
    let onExplore: () -> Void

    var body: some View {
        UnigridPanel(title: GuidePanel.parkMap.title) {
            VStack(alignment: .leading, spacing: 12) {
                ParkMapView(
                    place: place,
                    boundary: store.boundary(for: place.id),
                    sights: sights,
                    centres: centres,
                    interactive: false
                )
                .frame(height: 340)
                .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                .onTapGesture(perform: onExplore)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the park in 3D")

                Button(action: onExplore) {
                    Label("Explore in 3D", symbol: .explore3D)
                }
                .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
            }
        }
    }
}

/// A park on a map: tinted outline, numbered sights in rank order, visitor centres as
/// squares. Shared by the guide's map panel and the explorer.
struct ParkMapView: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let boundary: PlaceBoundary?
    var route: RouteLine?
    let sights: [PointOfInterest]
    let centres: [PointOfInterest]
    var interactive = true
    var position: Binding<MapCameraPosition>?
    var mapStyle: MapStyle = .standard(
        elevation: .realistic,
        emphasis: .muted,
        pointsOfInterest: .excludingAll
    )

    @State private var fallbackPosition: MapCameraPosition = .automatic

    var body: some View {
        let tint = style.siteTint(for: place)
        Map(position: position ?? $fallbackPosition, interactionModes: interactive ? .all : []) {
            if let boundary {
                ForEach(Array(boundary.polygons.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.exterior.map(\.clCoordinate))
                        .foregroundStyle(tint.opacity(0.14))
                        .stroke(tint, lineWidth: 1.6)
                }
            }
            if let route {
                ForEach(Array(route.paths.enumerated()), id: \.offset) { _, path in
                    MapPolyline(coordinates: path.map(\.clCoordinate))
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            if boundary == nil, route == nil {
                // A landmark is a point: mark it with its own pin.
                Annotation(place.name, coordinate: place.centre.clCoordinate) {
                    SitePin(place: place)
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(sights.enumerated()), id: \.element.id) { offset, sight in
                Annotation(sight.name, coordinate: sight.location.clCoordinate) {
                    SightNumber(number: offset + 1)
                }
                .annotationTitles(interactive ? .automatic : .hidden)
            }
            ForEach(centres) { centre in
                Annotation(centre.name, coordinate: centre.location.clCoordinate) {
                    Rectangle()
                        .fill(style.panel)
                        .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 2) }
                        .frame(width: 11, height: 11)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        .onAppear {
            if position == nil {
                fallbackPosition = .rect(MKMapRect(box: frame.expanded(by: 0.08)))
            }
        }
    }

    private var frame: BoundingBox {
        if let extent = boundary?.extent {
            return extent
        }
        if let extent = route?.extent {
            return extent.expanded(by: 0.1)
        }
        let points = (sights + centres).map(\.location) + [place.centre]
        return BoundingBox.enclosing(points)?.expanded(by: 0.3)
            ?? BoundingBox(
                south: place.centre.latitude - 0.2, west: place.centre.longitude - 0.2,
                north: place.centre.latitude + 0.2, east: place.centre.longitude + 0.2
            )
    }
}

/// A sight's number on a map, in the black square the guide's list uses.
struct SightNumber: View {
    @Environment(\.unigrid) private var style
    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 22
    let number: Int
    var isSelected = false

    var body: some View {
        Text("\(number)")
            .font(.custom("HelveticaNeue-Bold", size: 12, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(isSelected ? style.onAccent : style.bandInk)
            .frame(minWidth: side, minHeight: side)
            .background(isSelected ? style.accent : style.band)
            .overlay { Rectangle().strokeBorder(style.bandInk, lineWidth: 1) }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
