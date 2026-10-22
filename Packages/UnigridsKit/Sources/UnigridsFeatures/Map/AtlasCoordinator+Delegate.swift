import MapKit
import UnigridsCore

// MapKit's side of the atlas: the views for pins and clusters, the renderers for outlines
// and lines, selection, and what changes as the camera moves.

extension AtlasCoordinator {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let cluster = annotation as? MKClusterAnnotation {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: AtlasClusterView.reuse, for: cluster
            ) as? AtlasClusterView
            if let ink {
                let parks = cluster.memberAnnotations.allSatisfy {
                    ($0 as? PlaceAnnotation)?.tier == .nationalPark
                }
                view?.configure(count: cluster.memberAnnotations.count, ink: ink, parks: parks)
            }
            return view
        }
        if let focus = annotation as? FocusAnnotation {
            let view = MKMarkerAnnotationView(annotation: focus, reuseIdentifier: nil)
            view.markerTintColor = ink?.seal.platform
            view.displayPriority = .required
            view.titleVisibility = .visible
            return view
        }
        if let station = annotation as? StationAnnotation {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: StationMarkerView.reuse, for: station
            ) as? StationMarkerView
            if let ink {
                view?.configure(station: station, ink: ink, latitudeSpan: latitudeSpan)
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
        if let overlay = overlay as? TransportOverlay {
            let renderer = TransportRenderer(multiPolyline: overlay)
            if let ink {
                renderer.apply(ink.transportStyle(overlay.layer))
            }
            return renderer
        }
        if let overlay = overlay as? RouteOverlay {
            let renderer = MKMultiPolylineRenderer(multiPolyline: overlay)
            if let item = placesByID[overlay.placeID] {
                styleRoute(renderer, for: item)
            }
            routeRenderers[overlay.placeID] = renderer
            return renderer
        }
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

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        // MapKit deselects a pin when the map is tapped elsewhere; the tap handler decides
        // what that tap selected, so nothing to do here except keep the emphasis honest.
        (view as? AtlasMarkerView)?.isEmphasised = (view.annotation as? PlaceAnnotation)?
            .placeID == selected
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
        let span = mapView.region.span.latitudeDelta
        let crossedLabelThreshold = Self.labelBand(span) != Self.labelBand(latitudeSpan)
        let crossedOutlineThreshold = (span > MapDetail.allOutlinesSpan)
            != (latitudeSpan > MapDetail.allOutlinesSpan)
        let crossedParkThreshold = (span > MapDetail.compactParkSpan)
            != (latitudeSpan > MapDetail.compactParkSpan)
        latitudeSpan = span
        if crossedOutlineThreshold {
            syncAnnotations(allPlaces, on: mapView, restyleAll: false)
        }
        if crossedParkThreshold {
            reclusterParks(on: mapView)
        }
        syncOverlays(on: mapView, restyleAll: false)
        if let parent {
            syncTransport(parent, on: mapView, restyleAll: false)
        }
        if crossedLabelThreshold {
            for annotation in annotations.values {
                restyleMarker(for: annotation, on: mapView)
            }
            for station in stationAnnotations {
                if let ink, let view = mapView.view(for: station) as? StationMarkerView {
                    view.configure(station: station, ink: ink, latitudeSpan: span)
                }
            }
        }
        parent?.onRegionChange(mapView.region)
    }

    /// National parks join or leave their country-scale cluster. MapKit reads a pin's
    /// cluster when the pin is added, so they are put back on the map to be read again —
    /// all but the selected one, which stays where the reader is looking.
    func reclusterParks(on mapView: MKMapView) {
        let parks = annotations.values.filter {
            $0.tier == .nationalPark && $0.placeID != selected
        }
        mapView.removeAnnotations(parks)
        mapView.addAnnotations(parks)
    }

    static func labelBand(_ span: Double) -> [Bool] {
        PlaceTier.allCases.flatMap {
            [
                MapDetail.showsLabel(for: $0, latitudeSpan: span),
                MapDetail.showsPictogram(for: $0, latitudeSpan: span),
            ]
        } + [span <= MapDetail.stationSpan / 2, span > MapDetail.compactParkSpan]
    }
}

// MARK: - Focus

extension AtlasCoordinator {
    /// Mark the sight search chose, replacing any earlier mark.
    func syncFocus(_ wanted: AtlasFocus?, on map: MKMapView) {
        guard focus != wanted else { return }
        focus = wanted
        if let old = focusAnnotation {
            map.removeAnnotation(old)
        }
        focusAnnotation = wanted.map { focus in
            let annotation = FocusAnnotation()
            annotation.coordinate = focus.coordinate.clCoordinate
            annotation.title = focus.name
            return annotation
        }
        if let focusAnnotation {
            map.addAnnotation(focusAnnotation)
        }
    }
}
