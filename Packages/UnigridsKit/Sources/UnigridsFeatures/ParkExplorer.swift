import MapKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// 3D park exploration (SPECIFICATION.md §7): Apple's terrain and imagery with the park's
/// structure drawn on top — outline, numbered sights, visitor centres — a camera that
/// flies to a sight when it is chosen, and a guided fly-through of the sights in rank
/// order. Online only; Apple's 3D needs a connection.
struct ParkExplorer: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss

    let place: Place

    @State private var position: MapCameraPosition = .automatic
    @State private var current: Int?
    @State private var imagery = true
    @State private var tour: Task<Void, Never>?

    private var sights: [PointOfInterest] {
        store.sights(in: place.id)
    }

    var body: some View {
        NavigationStack {
            ParkMapView(
                place: place,
                boundary: store.boundary(for: place.id),
                sights: sights,
                centres: store.visitorCentres(in: place.id),
                interactive: true,
                position: $position,
                mapStyle: imagery
                    ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                    : .standard(
                        elevation: .realistic,
                        emphasis: .muted,
                        pointsOfInterest: .excludingAll
                    )
            )
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !sights.isEmpty {
                    SightStrip(sights: sights, current: current) { index in
                        stopTour()
                        fly(to: index)
                    }
                }
            }
            .navigationTitle(place.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onAppear { overview(animated: false) }
            .onDisappear { stopTour() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem {
            Button {
                imagery.toggle()
            } label: {
                Label(
                    imagery ? "Map" : "Satellite",
                    systemImage: imagery ? "map" : "globe.americas"
                )
            }
        }
        ToolbarItem {
            Button {
                stopTour()
                overview(animated: true)
            } label: {
                Label("Whole park", systemImage: "arrow.counterclockwise")
            }
        }
        if !sights.isEmpty {
            ToolbarItem {
                Button {
                    if tour == nil {
                        startTour()
                    } else {
                        stopTour()
                    }
                } label: {
                    Label(
                        tour == nil ? "Fly-through" : "Stop",
                        systemImage: tour == nil ? "play.fill" : "stop.fill"
                    )
                }
            }
        }
    }

    private var frame: BoundingBox {
        store.frame(for: place)
    }

    private func overview(animated: Bool) {
        current = nil
        let box = frame
        let heightKm = (box.north - box.south) * 111
        let widthKm = (box.east - box.west) * 111 * cos(box.centre.latitude * .pi / 180)
        let distance = max(max(heightKm, widthKm) * 1000 * 2.2, 4000)
        let camera = MapCamera(
            centerCoordinate: box.centre.clCoordinate,
            distance: distance,
            heading: 0,
            pitch: 50
        )
        if animated {
            withAnimation(.easeInOut(duration: 2)) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }

    private func fly(to index: Int) {
        guard sights.indices.contains(index) else { return }
        current = index
        let sight = sights[index]
        // A gentle heading change per stop, so the fly-through reads as moving around the
        // park rather than zooming in and out of one view.
        let camera = MapCamera(
            centerCoordinate: sight.location.clCoordinate,
            distance: 2600,
            heading: Double(index * 40 % 360),
            pitch: 68
        )
        withAnimation(.easeInOut(duration: 3)) { position = .camera(camera) }
    }

    private func startTour() {
        tour = Task { @MainActor in
            for index in sights.indices {
                fly(to: index)
                try? await Task.sleep(for: .seconds(6))
                if Task.isCancelled {
                    return
                }
            }
            overview(animated: true)
            tour = nil
        }
    }

    private func stopTour() {
        tour?.cancel()
        tour = nil
    }
}

/// The sights along the bottom of the explorer, numbered as in the guide.
struct SightStrip: View {
    @Environment(\.unigrid) private var style
    let sights: [PointOfInterest]
    let current: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current, sights.indices.contains(current),
               let summary = sights[current].summary
            {
                Text(summary)
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.bandInk)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: 680, alignment: .leading)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(sights.enumerated()), id: \.element.id) { index, sight in
                        Button {
                            onSelect(index)
                        } label: {
                            HStack(spacing: 8) {
                                SightNumber(number: index + 1, isSelected: index == current)
                                Text(sight.name)
                                    .font(UnigridStyle.action)
                                    .foregroundStyle(style.bandInk)
                                    .lineLimit(1)
                            }
                            .padding(.trailing, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(style.band)
    }
}
