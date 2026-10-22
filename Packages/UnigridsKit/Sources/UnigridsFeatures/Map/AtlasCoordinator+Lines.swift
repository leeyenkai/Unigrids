import MapKit
import UnigridsCore

// The atlas's lines: scenic byways, and the transport layers with their stations. An
// extension of the coordinator rather than part of its body, so the coordinator reads as
// pins and outlines and this file as roads and rail.

extension AtlasCoordinator {
    /// Byways are lines, drawn from regional zoom (`MapDetail.showsRoute`).
    func syncRoutes(on map: MKMapView, visible _: BoundingBox) {
        guard let parent else { return }
        var wanted: [UnigridsID: RouteOverlay] = [:]
        if MapDetail.showsRoute(latitudeSpan: latitudeSpan) {
            for (id, route) in parent.routes where placesByID[id] != nil {
                wanted[id] = routeCache[id] ?? routeOverlay(id: id, route: route)
            }
        }
        let gone = shownRoutes.keys.filter { wanted[$0] == nil }
        map.removeOverlays(gone.compactMap { shownRoutes.removeValue(forKey: $0) })
        for id in gone {
            routeRenderers[id] = nil
        }
        let firstTransport = transportOverlays.values.first
        for (id, overlay) in wanted where shownRoutes[id] == nil {
            shownRoutes[id] = overlay
            if let firstTransport {
                map.insertOverlay(overlay, below: firstTransport)
            } else {
                map.addOverlay(overlay, level: .aboveRoads)
            }
        }
    }

    func routeOverlay(id: UnigridsID, route: RouteLine) -> RouteOverlay {
        let lines = route.paths.map { path in
            let points = path.map(\.clCoordinate)
            return MKPolyline(coordinates: points, count: points.count)
        }
        let overlay = RouteOverlay(lines)
        overlay.placeID = id
        routeCache[id] = overlay
        return overlay
    }

    func restyleRoute(_ id: UnigridsID?) {
        guard let id, let renderer = routeRenderers[id], let item = placesByID[id] else { return }
        styleRoute(renderer, for: item)
        renderer.setNeedsDisplay()
    }

    func styleRoute(_ renderer: MKMultiPolylineRenderer, for item: AtlasPlace) {
        guard let ink else { return }
        let isSelected = item.place.id == selected
        renderer.strokeColor = ink.tint(for: item.place).platform
        renderer.lineWidth = isSelected ? 5 : 3
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.lineDashPattern = item.status == .planned && !isSelected ? [6, 4] : nil
    }

    // MARK: Transport

    /// One overlay per switched-on layer, rebuilt only when the network arrives; stations
    /// join the rail layer close up.
    func syncTransport(_ view: AtlasMapView, on map: MKMapView, restyleAll: Bool) {
        let signature = view.transport.signature
        if transportSignature != signature {
            transportSignature = signature
            map.removeOverlays(Array(transportOverlays.values))
            transportOverlays = [:]
            map.removeAnnotations(stationAnnotations)
            stationAnnotations = []
        }
        for layer in TransportLayer.allCases {
            let wanted = view.layers.contains(layer) && latitudeSpan <= layer.maximumSpan
            if wanted, transportOverlays[layer] == nil {
                let lines = view.transport.lines(for: layer).flatMap(\.paths).map { path in
                    let points = path.map(\.clCoordinate)
                    return MKPolyline(coordinates: points, count: points.count)
                }
                guard !lines.isEmpty else { continue }
                let overlay = TransportOverlay(lines)
                overlay.layer = layer
                transportOverlays[layer] = overlay
                // Above everything on the roads level: a road over a park reads, a park's
                // tint over a road does not.
                map.addOverlay(overlay, level: .aboveRoads)
            } else if !wanted, let overlay = transportOverlays.removeValue(forKey: layer) {
                map.removeOverlay(overlay)
            } else if restyleAll {
                restyle(layer, on: map)
            }
        }
        syncStations(view, on: map)
    }

    private func restyle(_ layer: TransportLayer, on map: MKMapView) {
        guard let overlay = transportOverlays[layer], let ink else { return }
        guard let renderer = map.renderer(for: overlay) as? TransportRenderer else { return }
        renderer.apply(ink.transportStyle(layer))
        renderer.setNeedsDisplay()
    }

    func syncStations(_ view: AtlasMapView, on map: MKMapView) {
        let wanted = view.layers.contains(.amtrak) && latitudeSpan <= MapDetail.stationSpan
        if wanted, stationAnnotations.isEmpty {
            stationAnnotations = view.transport.amtrakStations.map(StationAnnotation.init)
            map.addAnnotations(stationAnnotations)
        } else if !wanted, !stationAnnotations.isEmpty {
            map.removeAnnotations(stationAnnotations)
            stationAnnotations = []
        }
    }

    /// The byway a tap landed on: the nearest drawn line within a finger's width.
    func route(near point: Coordinate, in map: MKMapView) -> UnigridsID? {
        guard let parent, !shownRoutes.isEmpty, map.bounds.width > 0 else { return nil }
        let metresPerPoint = map.visibleMapRect.width / Double(map.bounds.width)
            * MKMetersPerMapPointAtLatitude(point.latitude)
        let reach = metresPerPoint * 14
        return shownRoutes.keys
            .compactMap { id -> (UnigridsID, Double)? in
                guard let route = parent.routes[id] else { return nil }
                let distance = route.distance(to: point)
                return distance <= reach ? (id, distance) : nil
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
