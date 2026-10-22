import MapKit
import SwiftUI
import UnigridsCore
import UnigridsReference

/// The offline Park map: a pack's tiles in place of Apple's map, with the park's trails,
/// numbered sights, visitor centres and campgrounds on top, and the reader's position when
/// they have shared it. An `MKMapView`, since SwiftUI's `Map` takes no tile overlay.
@MainActor
struct ParkTileMapView {
    struct Inks: Equatable {
        let trail: PlatformColor
        let focus: PlatformColor
        let marker: PlatformColor
    }

    let pack: OfflinePack
    let trails: [Trail]
    let sights: [PointOfInterest]
    let facilities: [PointOfInterest]
    var focusTrail: UnigridsID?
    var showsUserLocation = false
    let inks: Inks
    /// A request to move the camera, by identity like the atlas's.
    var camera: AtlasCameraRequest?

    func makeCoordinator() -> ParkTileCoordinator {
        ParkTileCoordinator()
    }

    private func makeMap(_ coordinator: ParkTileCoordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.addOverlay(PackTileOverlay(pack: pack), level: .aboveLabels)
        // Held to the pack: no panning off its tiles, no zooming past what they can show.
        map.cameraBoundary = MKMapView.CameraBoundary(mapRect: pack.rendered.mapRect)
        let latitude = pack.park.centre.latitude
        map.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: Self.distance(
                zoom: pack.maxZoom + PackTileOverlay.overzoom, latitude: latitude
            ),
            maxCenterCoordinateDistance: Self.distance(zoom: pack.minZoom, latitude: latitude)
        )
        coordinator.inks = inks
        for trail in trails {
            let line = TrailLine(trail.paths.map { path in
                MKPolyline(coordinates: path.map(\.clCoordinate), count: path.count)
            })
            line.trailID = trail.id
            line.title = trail.name
            map.addOverlay(line, level: .aboveLabels)
        }
        map.addAnnotations(sights.enumerated().map { index, sight in
            ParkMarker(poi: sight, number: index + 1)
        })
        map.addAnnotations(facilities.map { ParkMarker(poi: $0, number: nil) })
        let start = focusTrail.flatMap { id in trails.first { $0.id == id }?.extent }
            ?? pack.park
        map.setVisibleMapRect(
            start.mapRect,
            edgePadding: Self.padding,
            animated: false
        )
        update(map, coordinator)
        return map
    }

    private func update(_ map: MKMapView, _ coordinator: ParkTileCoordinator) {
        if map.showsUserLocation != showsUserLocation {
            map.showsUserLocation = showsUserLocation
        }
        if coordinator.focusTrail != focusTrail || coordinator.inks != inks {
            coordinator.focusTrail = focusTrail
            coordinator.inks = inks
            for case let line as TrailLine in map.overlays {
                guard let renderer = map.renderer(for: line) as? MKMultiPolylineRenderer
                else { continue }
                coordinator.style(renderer, for: line)
                renderer.setNeedsDisplay()
            }
        }
        if let request = camera, request.id != coordinator.lastCameraID {
            coordinator.lastCameraID = request.id
            DispatchQueue.main.async { [weak map] in
                map?.setVisibleMapRect(
                    request.box.mapRect, edgePadding: Self.padding, animated: request.animated
                )
            }
        }
    }

    private static let padding = PlatformEdgeInsets(top: 40, left: 30, bottom: 60, right: 30)

    /// Roughly how far above the ground the camera is when the map shows `zoom`'s tiles
    /// at their own size on a phone-sized view.
    static func distance(zoom: Int, latitude: Double) -> CLLocationDistance {
        let metresPerPixel = 156_543.03 * cos(latitude * .pi / 180) / pow(2, Double(zoom))
        return metresPerPixel * 900
    }
}

#if os(iOS)
    typealias PlatformEdgeInsets = UIEdgeInsets

    extension ParkTileMapView: UIViewRepresentable {
        func makeUIView(context: Context) -> MKMapView {
            makeMap(context.coordinator)
        }

        func updateUIView(_ map: MKMapView, context: Context) {
            update(map, context.coordinator)
        }
    }
#else
    typealias PlatformEdgeInsets = NSEdgeInsets

    extension ParkTileMapView: NSViewRepresentable {
        func makeNSView(context: Context) -> MKMapView {
            makeMap(context.coordinator)
        }

        func updateNSView(_ map: MKMapView, context: Context) {
            update(map, context.coordinator)
        }
    }
#endif

/// A trail's line on the Park map.
final class TrailLine: MKMultiPolyline {
    var trailID: UnigridsID?
}

/// A sight, numbered in rank order, or a visitor centre or campground.
final class ParkMarker: NSObject, MKAnnotation {
    let poi: PointOfInterest
    let number: Int?

    init(poi: PointOfInterest, number: Int?) {
        self.poi = poi
        self.number = number
    }

    var coordinate: CLLocationCoordinate2D {
        poi.location.clCoordinate
    }

    var title: String? {
        poi.name
    }

    var subtitle: String? {
        poi.kind.name
    }
}

@MainActor
final class ParkTileCoordinator: NSObject, MKMapViewDelegate {
    var inks: ParkTileMapView.Inks?
    var focusTrail: UnigridsID?
    var lastCameraID: UUID?

    func mapView(_: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let tiles = overlay as? PackTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tiles)
        }
        if let line = overlay as? TrailLine {
            let renderer = MKMultiPolylineRenderer(multiPolyline: line)
            style(renderer, for: line)
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func style(_ renderer: MKMultiPolylineRenderer, for line: TrailLine) {
        let focused = line.trailID != nil && line.trailID == focusTrail
        renderer.strokeColor = focused ? inks?.focus : inks?.trail
        renderer.lineWidth = focused ? 5 : 2.5
        renderer.lineCap = .round
        renderer.lineJoin = .round
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        guard let marker = annotation as? ParkMarker else { return nil }
        let view = MKMarkerAnnotationView(annotation: marker, reuseIdentifier: nil)
        view.markerTintColor = inks?.marker
        view.canShowCallout = true
        if let number = marker.number {
            view.glyphText = "\(number)"
            view.displayPriority = .required
        } else {
            view.glyphText = marker.poi.kind == .campground ? "▲" : "i"
            view.displayPriority = .defaultHigh
        }
        return view
    }
}
