import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The 3D explorer's map and its list of sights, trails and facilities (SPECIFICATION.md §7).

/// The explorer's map: outline, road, trails, sights, facilities.
struct ExplorerMap: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let boundary: PlaceBoundary?
    let route: RouteLine?
    let sights: [PointOfInterest]
    let facilities: [PointOfInterest]
    let trails: [Trail]
    let focus: ExplorerFocus?
    let mapStyle: ExplorerStyle
    @Binding var position: MapCameraPosition
    let onSelect: (ExplorerFocus) -> Void
    let onCameraChange: (BoundingBox) -> Void

    var body: some View {
        content.graphicTypeSize()
    }

    @ViewBuilder
    private var content: some View {
        // Over imagery the dark-scheme ink, which is the one lifted to show on a dark
        // ground: a national park's black outline would vanish into the terrain.
        let tint = mapStyle == .map ? style.siteTint(for: place)
            : Color(SiteInk.forPlace(place).value(.dark))
        Map(position: $position, interactionModes: .all) {
            if let boundary {
                ForEach(Array(boundary.polygons.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.exterior.map(\.clCoordinate))
                        .foregroundStyle(tint.opacity(0.12))
                        .stroke(tint, lineWidth: 2)
                }
            }
            if let route {
                ForEach(Array(route.paths.enumerated()), id: \.offset) { _, path in
                    MapPolyline(coordinates: path.map(\.clCoordinate))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            ForEach(trails) { trail in
                let isFocus = focus == .trail(trail.id)
                ForEach(Array(trail.paths.enumerated()), id: \.offset) { _, path in
                    MapPolyline(coordinates: path.map(\.clCoordinate))
                        .stroke(
                            isFocus ? style.accent : style.trail,
                            style: StrokeStyle(
                                lineWidth: isFocus ? 5 : 2.5,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: isFocus ? [] : [6, 3]
                            )
                        )
                }
            }
            ForEach(facilities) { poi in
                Annotation(poi.name, coordinate: poi.location.clCoordinate) {
                    Button { onSelect(.facility(poi.id)) } label: {
                        FacilityMarker(kind: poi.kind, isSelected: focus == .facility(poi.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(poi.kind.name), \(poi.name)")
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(sights.enumerated()), id: \.element.id) { offset, sight in
                Annotation(sight.name, coordinate: sight.location.clCoordinate) {
                    Button { onSelect(.sight(sight.id)) } label: {
                        SightNumber(number: offset + 1, isSelected: focus == .sight(sight.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sight \(offset + 1), \(sight.name)")
                }
            }
            if boundary == nil, route == nil {
                Annotation(place.name, coordinate: place.centre.clCoordinate) {
                    SitePin(place: place)
                }
            }
            UserAnnotation()
        }
        .mapStyle(mapStyle.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            #if os(iOS)
                MapPitchToggle()
                MapUserLocationButton()
            #else
                MapPitchSlider()
                MapZoomStepper()
            #endif
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            onCameraChange(BoundingBox(region: context.region))
        }
    }
}

/// A visitor centre or campground on the explorer's map.
struct FacilityMarker: View {
    @Environment(\.unigrid) private var style
    let kind: POIKind
    var isSelected = false

    var body: some View {
        Image(systemName: kind == .campground ? "tent.fill" : "info")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? style.onAccent : style.ink)
            .frame(width: 20, height: 20)
            .background(isSelected ? style.accent : style.panel)
            .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1.5) }
    }
}

/// Sights, trails and facilities, beside the map on a wide screen and in a sheet on a
/// narrow one. Choosing one moves the camera; panning dims what the camera cannot see.
struct ExplorerList: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let sights: [PointOfInterest]
    let trails: [Trail]
    let facilities: [PointOfInterest]
    let focus: ExplorerFocus?
    let visible: BoundingBox?
    let onSelect: (ExplorerFocus) -> Void

    var body: some View {
        List {
            if sights.isEmpty, trails.isEmpty, facilities.isEmpty {
                Text(
                    "No sights or trails are mapped for \(place.name). "
                        + "Pan, tilt and turn to explore it."
                )
                .font(UnigridStyle.prose)
                .foregroundStyle(style.inkSecondary)
                .listRowBackground(Color.clear)
            }
            if !sights.isEmpty {
                Section {
                    ForEach(Array(sights.enumerated()), id: \.element.id) { index, sight in
                        Button { onSelect(.sight(sight.id)) } label: {
                            HStack(spacing: 10) {
                                SightNumber(
                                    number: index + 1,
                                    isSelected: focus == .sight(sight.id)
                                )
                                Text(sight.name)
                                    .font(UnigridStyle.rowTitle)
                                    .foregroundStyle(style.ink)
                            }
                            .opacity(inView(sight.location) ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHead("Sights", detail: "\(sights.count)")
                }
            }
            if !trails.isEmpty {
                Section {
                    ForEach(trails.prefix(40)) { trail in
                        Button { onSelect(.trail(trail.id)) } label: {
                            TrailRow(trail: trail)
                                .opacity(trail.start.map(inView) ?? true ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(focus == .trail(trail.id) ? style.rule
                            .opacity(0.5) : Color.clear)
                    }
                    if trails.count > 40 {
                        ListNotes {
                            Text(
                                "The 40 longest of \(trails.count). Every trail is in the "
                                    + "park's trail catalogue."
                            )
                        }
                    }
                } header: {
                    SectionHead("Trails", detail: "\(trails.count)")
                }
            }
            if !facilities.isEmpty {
                Section {
                    ForEach(facilities) { poi in
                        Button { onSelect(.facility(poi.id)) } label: {
                            HStack(spacing: 10) {
                                FacilityMarker(
                                    kind: poi.kind,
                                    isSelected: focus == .facility(poi.id)
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(poi.name)
                                        .font(UnigridStyle.rowTitle)
                                        .foregroundStyle(style.ink)
                                    Text(poi.kind.name)
                                        .font(UnigridStyle.rowDetail)
                                        .foregroundStyle(style.inkSecondary)
                                }
                            }
                            .opacity(inView(poi.location) ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHead("Visitor centres and campgrounds", detail: "\(facilities.count)")
                }
            }
        }
        .listStyle(.plain)
        .paperPage()
    }

    private func inView(_ point: Coordinate) -> Bool {
        visible?.contains(point) ?? true
    }
}
