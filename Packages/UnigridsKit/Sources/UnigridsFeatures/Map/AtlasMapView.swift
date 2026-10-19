import MapKit
import SwiftUI
import UnigridsCore

#if os(iOS)
    import UIKit

    typealias PlatformColor = UIColor
#else
    import AppKit

    typealias PlatformColor = NSColor
#endif

/// One place as the atlas draws it.
struct AtlasPlace: Equatable {
    let place: Place
    let status: VisitStatusBadgeStatus
}

/// The base map under the outlines.
enum AtlasBasemap: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case imagery

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .standard: "Map"
        case .hybrid: "Hybrid"
        case .imagery: "Satellite"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "map.fill"
        case .imagery: "globe.americas"
        }
    }
}

/// A one-off instruction to move the camera. Each request carries its own identity, so
/// asking for the same box twice still moves the camera the second time.
struct AtlasCameraRequest: Equatable {
    let id = UUID()
    let box: BoundingBox
    var animated = true
}

/// The colours the atlas draws in, resolved once from the Unigrid style so the map and
/// the guides agree on what a national park looks like.
struct AtlasInk: Equatable {
    let scheme: PaletteScheme
    let paper: ColorValue
    let ink: ColorValue
    let band: ColorValue
    let bandInk: ColorValue

    init(scheme: PaletteScheme, palette: Palette) {
        let colors = palette.colors(scheme)
        self.scheme = scheme
        // Pins sit on map tiles no palette controls, so their paper is plain white or
        // black rather than brochure stock (docs/design-system.md, "Map pins").
        paper = scheme == .dark ? ColorValue(red: 0.11, green: 0.11, blue: 0.11)
            : ColorValue(red: 1, green: 1, blue: 1)
        ink = colors.ink
        band = colors.band
        bandInk = colors.bandInk
    }

    func tint(for place: Place) -> ColorValue {
        AgencyInk.forPlace(agency: place.agency, tier: place.tier).value(scheme)
    }
}

extension ColorValue {
    var platform: PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: 1)
    }

    var cg: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    func cg(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The map home screen's map: every covered place as a pin, its outline as a tinted
/// polygon, and a tap anywhere inside an outline selecting that place
/// (SPECIFICATION.md §5).
///
/// An `MKMapView` rather than SwiftUI's `Map`, for three things `Map` does not do: pin
/// clustering at country scale, a few hundred polygons added and removed as the camera
/// moves, and hit-testing a tap against those polygons. The spec anticipated the wrapper
/// for the offline tile overlay too (§3).
@MainActor
struct AtlasMapView {
    let places: [AtlasPlace]
    let boundaries: [UnigridsID: PlaceBoundary]
    let selection: UnigridsID?
    let camera: AtlasCameraRequest?
    let basemap: AtlasBasemap
    let ink: AtlasInk
    let onSelect: (UnigridsID?) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeCoordinator() -> AtlasCoordinator {
        AtlasCoordinator()
    }

    private func makeMap(_ coordinator: AtlasCoordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.showsCompass = true
        map.showsScale = true
        map.register(
            AtlasMarkerView.self,
            forAnnotationViewWithReuseIdentifier: AtlasMarkerView.reuse
        )
        map.register(
            AtlasClusterView.self,
            forAnnotationViewWithReuseIdentifier: AtlasClusterView.reuse
        )
        coordinator.attach(to: map)
        map.setRegion(Self.lower48, animated: false)
        update(map, coordinator)
        return map
    }

    private func update(_ map: MKMapView, _ coordinator: AtlasCoordinator) {
        coordinator.parent = self
        coordinator.apply(self)
    }

    /// The lower 48, framed. Alaska, Hawaii and the territories are a tap away through the
    /// region shortcuts rather than by zooming out until nothing is legible.
    static let lower48 = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: -97.5),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 58)
    )
}

#if os(iOS)
    extension AtlasMapView: UIViewRepresentable {
        func makeUIView(context: Context) -> MKMapView {
            makeMap(context.coordinator)
        }

        func updateUIView(_ map: MKMapView, context: Context) {
            update(map, context.coordinator)
        }
    }
#else
    extension AtlasMapView: NSViewRepresentable {
        func makeNSView(context: Context) -> MKMapView {
            makeMap(context.coordinator)
        }

        func updateNSView(_ map: MKMapView, context: Context) {
            update(map, context.coordinator)
        }
    }
#endif

// MARK: - Coordinator

@MainActor
final class AtlasCoordinator: NSObject, MKMapViewDelegate {
    var parent: AtlasMapView?
    private weak var map: MKMapView?

    private var annotations: [UnigridsID: PlaceAnnotation] = [:]
    private var overlayCache: [UnigridsID: PlaceOverlay] = [:]
    private var shownOverlays: [UnigridsID: PlaceOverlay] = [:]
    private var renderers: [UnigridsID: MKMultiPolygonRenderer] = [:]
    private var placesByID: [UnigridsID: AtlasPlace] = [:]

    private var ink: AtlasInk?
    private var basemap: AtlasBasemap?
    private var lastCameraID: UUID?
    private var selected: UnigridsID?
    private var latitudeSpan: Double = AtlasMapView.lower48.span.latitudeDelta

    func attach(to map: MKMapView) {
        self.map = map
        #if os(iOS)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            map.addGestureRecognizer(tap)
        #else
            let click = NSClickGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            click.delegate = self
            map.addGestureRecognizer(click)
        #endif
    }

    func apply(_ view: AtlasMapView) {
        guard let map else { return }

        if basemap != view.basemap {
            basemap = view.basemap
            map.preferredConfiguration = Self.configuration(for: view.basemap)
        }

        let inkChanged = ink != view.ink
        ink = view.ink
        syncAnnotations(view.places, on: map, restyleAll: inkChanged)
        syncOverlays(on: map, restyleAll: inkChanged)

        if selected != view.selection {
            let previous = selected
            selected = view.selection
            restyleOverlay(previous)
            restyleOverlay(selected)
            if let previous, let annotation = annotations[previous] {
                map.deselectAnnotation(annotation, animated: true)
                (map.view(for: annotation) as? AtlasMarkerView)?.isEmphasised = false
            }
            if let selected, let annotation = annotations[selected] {
                map.selectAnnotation(annotation, animated: true)
                (map.view(for: annotation) as? AtlasMarkerView)?.isEmphasised = true
            }
        }

        if let request = view.camera, request.id != lastCameraID {
            lastCameraID = request.id
            // Not inside the SwiftUI update: MapKit drops a camera change made during the
            // layout pass that delivers it, and the move then lands one request late.
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, lastCameraID == request.id else { return }
                move(map, to: request.box, animated: request.animated)
            }
        }
    }

    // MARK: Annotations

    private func syncAnnotations(_ places: [AtlasPlace], on map: MKMapView, restyleAll: Bool) {
        let incoming = Dictionary(places.map { ($0.place.id, $0) }, uniquingKeysWith: { a, _ in a })
        let removed = annotations.keys.filter { incoming[$0] == nil }
        map.removeAnnotations(removed.compactMap { annotations.removeValue(forKey: $0) })

        var added: [PlaceAnnotation] = []
        for (id, item) in incoming {
            if let existing = annotations[id] {
                if existing.status != item.status || restyleAll {
                    existing.status = item.status
                    restyleMarker(for: existing, on: map)
                }
            } else {
                let annotation = PlaceAnnotation(item)
                annotations[id] = annotation
                added.append(annotation)
            }
        }
        map.addAnnotations(added)
        placesByID = incoming
    }

    private func restyleMarker(for annotation: PlaceAnnotation, on map: MKMapView) {
        guard let view = map.view(for: annotation) as? AtlasMarkerView, let ink else { return }
        view.configure(annotation: annotation, ink: ink, latitudeSpan: latitudeSpan)
    }

    // MARK: Outlines

    /// Outlines are drawn for the national parks always, and for everything else only at
    /// regional zoom and only where the camera is looking (`MapDetail`).
    private func syncOverlays(on map: MKMapView, restyleAll: Bool) {
        guard let parent else { return }
        let visible = BoundingBox(region: map.region).expanded(by: 0.5)
        var wanted: [UnigridsID: PlaceOverlay] = [:]
        for (id, item) in placesByID {
            guard let boundary = parent.boundaries[id],
                  MapDetail.showsOutline(for: item.place.tier, latitudeSpan: latitudeSpan),
                  item.place.tier == .nationalPark || boundary.extent.intersects(visible)
            else { continue }
            wanted[id] = overlay(for: item.place, boundary: boundary)
        }

        let gone = shownOverlays.keys.filter { wanted[$0] == nil }
        map.removeOverlays(gone.compactMap { shownOverlays.removeValue(forKey: $0) })
        for id in gone {
            renderers[id] = nil
        }
        let fresh = wanted.filter { shownOverlays[$0.key] == nil }
        for (id, overlay) in fresh {
            shownOverlays[id] = overlay
        }
        // Smaller tiers on top, so a state park inside a national forest stays tappable.
        let ordered = fresh.values.sorted { $0.tier.rawValue < $1.tier.rawValue }
        map.addOverlays(ordered, level: .aboveRoads)

        if restyleAll {
            for id in renderers.keys {
                restyleOverlay(id)
            }
        }
    }

    private func overlay(for place: Place, boundary: PlaceBoundary) -> PlaceOverlay {
        if let cached = overlayCache[place.id] {
            return cached
        }
        let polygons = boundary.polygons.map { polygon -> MKPolygon in
            let holes = polygon.holes.map { ring in
                let points = ring.map(\.clCoordinate)
                return MKPolygon(coordinates: points, count: points.count)
            }
            let points = polygon.exterior.map(\.clCoordinate)
            return MKPolygon(coordinates: points, count: points.count, interiorPolygons: holes)
        }
        let overlay = PlaceOverlay(polygons)
        overlay.placeID = place.id
        overlay.tier = place.tier
        overlayCache[place.id] = overlay
        return overlay
    }

    private func restyleOverlay(_ id: UnigridsID?) {
        guard let id, let renderer = renderers[id], let item = placesByID[id] else { return }
        style(renderer, for: item)
        renderer.setNeedsDisplay()
    }

    private func style(_ renderer: MKMultiPolygonRenderer, for item: AtlasPlace) {
        guard let ink else { return }
        let tint = ink.tint(for: item.place)
        let isSelected = item.place.id == selected
        let visited = item.status == .visited
        let base: Double = item.place.tier == .nationalPark ? 0.16 : 0.12
        renderer.fillColor = tint.platform.withAlphaComponent(
            isSelected ? 0.34 : (visited ? base + 0.1 : base)
        )
        renderer.strokeColor = (isSelected ? ink.ink : tint).platform
        renderer.lineWidth = isSelected ? 2.6 : (item.place.tier == .nationalPark ? 1.4 : 1)
        renderer.lineDashPattern = item.status == .planned && !isSelected ? [4, 3] : nil
    }

    // MARK: Camera

    private func move(_ map: MKMapView, to box: BoundingBox, animated: Bool) {
        let rect = MKMapRect(box: box)
        #if os(iOS)
            let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
        #else
            let padding = NSEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
        #endif
        map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
    }

    static func configuration(for basemap: AtlasBasemap) -> MKMapConfiguration {
        switch basemap {
        case .standard:
            // Muted, so the park outlines carry the colour and the base map recedes the
            // way the base layer of a brochure map does.
            let configuration = MKStandardMapConfiguration(
                elevationStyle: .realistic, emphasisStyle: .muted
            )
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .hybrid:
            let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .imagery:
            return MKImageryMapConfiguration(elevationStyle: .realistic)
        }
    }

    // MARK: Taps

    @objc func handleTap(_ recognizer: AnyObject) {
        guard let map, let parent else { return }
        #if os(iOS)
            guard let gesture = recognizer as? UITapGestureRecognizer else { return }
            let point = gesture.location(in: map)
        #else
            guard let gesture = recognizer as? NSClickGestureRecognizer else { return }
            let point = gesture.location(in: map)
        #endif
        // A tap on a pin is MapKit's to handle; it selects the pin itself.
        if annotation(near: point, in: map) != nil {
            return
        }
        let coordinate = map.convert(point, toCoordinateFrom: map)
        let candidates = shownOverlays.keys.compactMap { placesByID[$0]?.place }
        let tapped = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let hit = candidates
            .compactMap { place -> (UnigridsID, Double)? in
                guard let boundary = parent.boundaries[place.id], boundary.contains(tapped)
                else { return nil }
                return (place.id, boundary.extent.degreeArea)
            }
            .min { $0.1 < $1.1 }?
            .0
        parent.onSelect(hit)
    }

    private func annotation(near point: CGPoint, in map: MKMapView) -> MKAnnotation? {
        let slop: CGFloat = 18
        for annotation in map.annotations(in: map.visibleMapRect) {
            guard let annotation = annotation as? MKAnnotation else { continue }
            let pinPoint = map.convert(annotation.coordinate, toPointTo: map)
            if abs(pinPoint.x - point.x) < slop, abs(pinPoint.y - point.y) < slop {
                return annotation
            }
        }
        return nil
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let cluster = annotation as? MKClusterAnnotation {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: AtlasClusterView.reuse, for: cluster
            ) as? AtlasClusterView
            if let ink {
                view?.configure(count: cluster.memberAnnotations.count, ink: ink)
            }
            return view
        }
        guard let annotation = annotation as? PlaceAnnotation, let ink else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: AtlasMarkerView.reuse, for: annotation
        ) as? AtlasMarkerView
        view?.configure(annotation: annotation, ink: ink, latitudeSpan: latitudeSpan)
        view?.isEmphasised = annotation.placeID == selected
        return view
    }

    func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let overlay = overlay as? PlaceOverlay, let item = placesByID[overlay.placeID] else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKMultiPolygonRenderer(multiPolygon: overlay)
        style(renderer, for: item)
        renderers[overlay.placeID] = renderer
        return renderer
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        let annotation = view.annotation
        if let cluster = annotation as? MKClusterAnnotation {
            // A cluster is a promise of more pins; keep it, by zooming to show them.
            mapView.deselectAnnotation(cluster, animated: false)
            mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            return
        }
        guard let annotation = annotation as? PlaceAnnotation else { return }
        if annotation.placeID != selected {
            parent?.onSelect(annotation.placeID)
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
        let span = mapView.region.span.latitudeDelta
        let crossedLabelThreshold = Self.labelBand(span) != Self.labelBand(latitudeSpan)
        latitudeSpan = span
        syncOverlays(on: mapView, restyleAll: false)
        if crossedLabelThreshold {
            for annotation in annotations.values {
                restyleMarker(for: annotation, on: mapView)
            }
        }
        parent?.onRegionChange(mapView.region)
    }

    private static func labelBand(_ span: Double) -> [Bool] {
        PlaceTier.allCases.map { MapDetail.showsLabel(for: $0, latitudeSpan: span) }
    }
}

#if os(iOS)
    extension AtlasCoordinator: UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
#else
    extension AtlasCoordinator: NSGestureRecognizerDelegate {
        func gestureRecognizer(
            _: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: NSGestureRecognizer
        ) -> Bool {
            true
        }
    }
#endif

// MARK: - Model objects MapKit needs

final class PlaceAnnotation: NSObject, MKAnnotation {
    let placeID: UnigridsID
    let tier: PlaceTier
    let place: Place
    var status: VisitStatusBadgeStatus
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ item: AtlasPlace) {
        place = item.place
        placeID = item.place.id
        tier = item.place.tier
        status = item.status
        coordinate = item.place.centre.clCoordinate
        title = item.place.name
        subtitle = item.place.designation
    }
}

final class PlaceOverlay: MKMultiPolygon {
    var placeID: UnigridsID = ""
    var tier: PlaceTier = .nationalPark
}

extension BoundingBox {
    init(region: MKCoordinateRegion) {
        self.init(
            south: region.center.latitude - region.span.latitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2,
            north: region.center.latitude + region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2
        )
    }
}

extension MKMapRect {
    init(box: BoundingBox) {
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: box.north, longitude: box.west))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: box.south, longitude: box.east))
        self.init(
            x: min(northWest.x, southEast.x),
            y: min(northWest.y, southEast.y),
            width: abs(southEast.x - northWest.x),
            height: abs(southEast.y - northWest.y)
        )
    }
}
