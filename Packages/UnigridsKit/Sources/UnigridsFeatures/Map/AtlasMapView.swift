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

/// A one-off instruction to move the camera. Each request carries its own identity, so
/// asking for the same box twice still moves the camera the second time.
struct AtlasCameraRequest: Equatable {
    let id = UUID()
    let box: BoundingBox
    var animated = true
    /// Points at the foot of the map that something covers — the iPhone's overview sheet —
    /// so the box is framed in what stays visible.
    var bottomInset: CGFloat = 0
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
    /// Changes whenever `places` does, so an update that changes nothing about them costs
    /// nothing: walking five thousand places and their outlines on every SwiftUI update
    /// stalled the map while a card slid in.
    var placesRevision = 0
    let boundaries: [UnigridsID: PlaceBoundary]
    let overviewBoundaries: [UnigridsID: PlaceBoundary]
    let routes: [UnigridsID: RouteLine]
    let transport: TransportNetwork
    let layers: Set<TransportLayer>
    let selection: UnigridsID?
    let camera: AtlasCameraRequest?
    let basemap: AtlasBasemap
    let ink: AtlasInk
    var showsUserLocation = false
    /// A sight to mark, chosen from search.
    var focus: AtlasFocus?
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
        map.register(
            StationMarkerView.self,
            forAnnotationViewWithReuseIdentifier: StationMarkerView.reuse
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
    weak var map: MKMapView?

    var annotations: [UnigridsID: PlaceAnnotation] = [:]
    var overlayCache: [UnigridsID: PlaceOverlay] = [:]
    var overviewCache: [UnigridsID: PlaceOverlay] = [:]
    var shownOverlays: [UnigridsID: PlaceOverlay] = [:]
    var renderers: [UnigridsID: MKMultiPolygonRenderer] = [:]
    var placesByID: [UnigridsID: AtlasPlace] = [:]

    var routeCache: [UnigridsID: RouteOverlay] = [:]
    var shownRoutes: [UnigridsID: RouteOverlay] = [:]
    var routeRenderers: [UnigridsID: MKMultiPolylineRenderer] = [:]

    var transportOverlays: [TransportLayer: TransportOverlay] = [:]
    /// What the overlays were built from, by count: the network arrives once, and
    /// comparing the whole of it on every SwiftUI update would cost more than drawing it.
    var transportSignature = 0
    var stationAnnotations: [StationAnnotation] = []

    var ink: AtlasInk?
    var basemap: AtlasBasemap?
    var lastCameraID: UUID?
    var selected: UnigridsID?
    var focus: AtlasFocus?
    var focusAnnotation: FocusAnnotation?
    var placesRevision: Int?
    var latitudeSpan: Double = AtlasMapView.lower48.span.latitudeDelta

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

        if map.showsUserLocation != view.showsUserLocation {
            map.showsUserLocation = view.showsUserLocation
        }

        let inkChanged = ink != view.ink
        ink = view.ink
        // The camera's own moves re-sync from `regionDidChange`; here, only new places or
        // inks need it.
        if inkChanged || placesRevision != view.placesRevision {
            placesRevision = view.placesRevision
            syncAnnotations(view.places, on: map, restyleAll: inkChanged)
            syncOverlays(on: map, restyleAll: inkChanged)
        }
        syncTransport(view, on: map, restyleAll: inkChanged)
        syncFocus(view.focus, on: map)

        if selected != view.selection {
            let previous = selected
            selected = view.selection
            restyleOverlay(previous)
            restyleOverlay(selected)
            restyleRoute(previous)
            restyleRoute(selected)
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
                move(
                    map,
                    to: request.box,
                    animated: request.animated,
                    bottomInset: request.bottomInset
                )
            }
        }
    }

    // MARK: Annotations

    var allPlaces: [AtlasPlace] = []

    /// Every place the filter lets through is outlined; only those `MapDetail` pins at
    /// this zoom get an annotation.
    func syncAnnotations(_ places: [AtlasPlace], on map: MKMapView, restyleAll: Bool) {
        allPlaces = places
        placesByID = Dictionary(places.map { ($0.place.id, $0) }, uniquingKeysWith: { a, _ in a })
        let span = latitudeSpan
        let incoming = placesByID.filter {
            MapDetail.showsPin(for: $0.value.place.kind, latitudeSpan: span)
        }
        let removed = annotations.keys.filter { incoming[$0] == nil }
        map.removeAnnotations(removed.compactMap { annotations.removeValue(forKey: $0) })

        var added: [PlaceAnnotation] = []
        for (id, item) in incoming {
            if let existing = annotations[id] {
                if existing.status != item.status || existing.alert != item.alert || restyleAll {
                    existing.status = item.status
                    existing.alert = item.alert
                    restyleMarker(for: existing, on: map)
                }
            } else {
                let annotation = PlaceAnnotation(item)
                annotations[id] = annotation
                added.append(annotation)
            }
        }
        map.addAnnotations(added)
    }

    func restyleMarker(for annotation: PlaceAnnotation, on map: MKMapView) {
        guard let view = map.view(for: annotation) as? AtlasMarkerView, let ink else { return }
        view.configure(annotation: annotation, ink: ink, latitudeSpan: latitudeSpan)
    }

    // MARK: Outlines

    /// Every outline at every zoom (`MapDetail`): national parks at full detail always,
    /// everything else from the country-scale set until the camera comes in, and then at
    /// full detail where the camera is looking.
    func syncOverlays(on map: MKMapView, restyleAll: Bool) {
        guard let parent else { return }
        let visible = BoundingBox(region: map.region).expanded(by: 0.5)
        var wanted: [UnigridsID: PlaceOverlay] = [:]
        for (id, item) in placesByID {
            wanted[id] = wantedOverlay(for: item, in: parent, visible: visible)
        }

        // An outline swapped between detail levels is a different overlay object, and goes
        // out and back in like any other change.
        let gone = shownOverlays.keys
            .filter { wanted[$0] == nil || wanted[$0] !== shownOverlays[$0] }
        map.removeOverlays(gone.compactMap { shownOverlays.removeValue(forKey: $0) })
        for id in gone {
            renderers[id] = nil
        }
        let fresh = wanted.filter { shownOverlays[$0.key] == nil }
        for id in fresh.keys {
            renderers[id] = nil
        }
        for (id, overlay) in fresh {
            shownOverlays[id] = overlay
        }
        // Smaller tiers on top, so a state park inside a national forest stays tappable,
        // and every outline beneath the lines — byways and roads read over a park's tint.
        let ordered = fresh.values.sorted { $0.tier.rawValue > $1.tier.rawValue }
        for overlay in ordered {
            map.insertOverlay(overlay, at: 0, level: .aboveRoads)
        }

        syncRoutes(on: map, visible: visible)

        if restyleAll {
            for id in renderers.keys {
                restyleOverlay(id)
            }
            for id in routeRenderers.keys {
                restyleRoute(id)
            }
        }
    }

    /// The outline to draw for a place at the current zoom, or `nil` for none.
    func wantedOverlay(
        for item: AtlasPlace, in parent: AtlasMapView, visible: BoundingBox
    ) -> PlaceOverlay? {
        let tier = item.place.tier
        guard MapDetail.showsOutline(for: tier, latitudeSpan: latitudeSpan) else { return nil }
        if MapDetail.usesOverviewOutline(for: tier, latitudeSpan: latitudeSpan) {
            guard let boundary = parent.overviewBoundaries[item.place.id] else { return nil }
            return overlay(for: item.place, boundary: boundary, overview: true)
        }
        guard let boundary = parent.boundaries[item.place.id] else { return nil }
        guard tier == .nationalPark || boundary.extent.intersects(visible) else { return nil }
        return overlay(for: item.place, boundary: boundary, overview: false)
    }

    func overlay(
        for place: Place,
        boundary: PlaceBoundary,
        overview: Bool
    ) -> PlaceOverlay {
        if let cached = overview ? overviewCache[place.id] : overlayCache[place.id] {
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
        overlay.isOverview = overview
        if overview {
            overviewCache[place.id] = overlay
        } else {
            overlayCache[place.id] = overlay
        }
        return overlay
    }

    func restyleOverlay(_ id: UnigridsID?) {
        guard let id, let renderer = renderers[id], let item = placesByID[id] else { return }
        style(renderer, for: item)
        renderer.setNeedsDisplay()
    }

    func style(_ renderer: MKMultiPolygonRenderer, for item: AtlasPlace) {
        guard let ink else { return }
        let tint = ink.tint(for: item.place)
        let isSelected = item.place.id == selected
        let visited = item.status == .visited
        let overview = (renderer.overlay as? PlaceOverlay)?.isOverview == true
        // At country scale the lands are a patchwork read as a whole, so they are tinted
        // a touch lighter and ruled finer than when one of them fills the screen.
        let base: Double = item.place.tier == .nationalPark ? 0.18 : (overview ? 0.14 : 0.12)
        renderer.fillColor = tint.platform.withAlphaComponent(
            isSelected ? 0.34 : (visited ? base + 0.1 : base)
        )
        renderer.strokeColor = (isSelected ? ink.ink : tint).platform
        renderer.lineWidth = isSelected ? 2.6
            : (item.place.tier == .nationalPark ? 1.4 : (overview ? 0.6 : 1))
        renderer.lineDashPattern = item.status == .planned && !isSelected ? [4, 3] : nil
    }

    // MARK: Camera

    func move(_ map: MKMapView, to box: BoundingBox, animated: Bool, bottomInset: CGFloat) {
        let rect = MKMapRect(box: box)
        #if os(iOS)
            let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60 + bottomInset, right: 40)
        #else
            let padding = NSEdgeInsets(top: 60, left: 40, bottom: 60 + bottomInset, right: 40)
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
        let tapped = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let byway = route(near: tapped, in: map) {
            parent.onSelect(byway)
            return
        }
        let candidates = shownOverlays.keys.compactMap { placesByID[$0]?.place }
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

    func annotation(near point: CGPoint, in map: MKMapView) -> MKAnnotation? {
        let slop: CGFloat = 18
        for annotation in map.annotations(in: map.visibleMapRect) {
            guard let annotation = annotation as? MKAnnotation,
                  !(annotation is MKUserLocation) else { continue }
            let pinPoint = map.convert(annotation.coordinate, toPointTo: map)
            if abs(pinPoint.x - point.x) < slop, abs(pinPoint.y - point.y) < slop {
                return annotation
            }
        }
        return nil
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
