import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The map the app opens on (SPECIFICATION.md §5).
///
/// National parks are always visible; the other tiers arrive with the pipeline, and the
/// filter row already carries the tier control so the shape of that is settled.
public struct MapScreen: View {
    @Environment(\.referenceStore) private var store
    @Query private var visits: [Visit]

    @State private var camera: MapCameraPosition = .region(Self.unitedStates)
    @State private var selected: Place?
    @State private var query = ""
    @State private var showVisitedOnly = false

    public init() {}

    /// The lower 48, framed. Alaska, Hawaii and the territories are a tap away through
    /// the region shortcuts rather than by zooming out until nothing is legible.
    private static let unitedStates = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 32, longitudeDelta: 58)
    )

    private var index: VisitIndex {
        VisitIndex(visits: visits)
    }

    private var places: [Place] {
        let base = query.isEmpty ? store.nationalParks : store.search(query)
        guard showVisitedOnly else { return base }
        return base.filter { index.visitedPlaceIDs.contains($0.id) }
    }

    public var body: some View {
        NavigationStack {
            Map(position: $camera) {
                ForEach(places) { place in
                    Annotation(
                        place.name,
                        coordinate: place.centre.clCoordinate,
                        anchor: .bottom
                    ) {
                        ParkPin(
                            place: place,
                            status: index.status(for: place.id)
                        )
                        .onTapGesture { selected = place }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                RegionShortcutBar(camera: $camera)
            }
            .searchable(text: $query, prompt: "Parks, sights and visitor centres")
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem {
                    Toggle(isOn: $showVisitedOnly) {
                        Label("Visited only", systemImage: "checkmark.circle")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(item: $selected) { place in
                PlaceCardSheet(place: place)
            }
        }
    }
}

/// A pin on the map: colour by agency, symbol by kind, filled when visited.
struct ParkPin: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let status: VisitStatusBadgeStatus

    var body: some View {
        let tint = PlaceStyle.tint(for: place, in: style)
        return Image(systemName: PlaceStyle.symbol(for: place))
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .visited ? .white : tint)
            .frame(width: 28, height: 28)
            .background {
                // Visited places show filled, unvisited hollow (§5). `.background` is
                // the cross-platform semantic fill; `Color(.systemBackground)` is iOS-only.
                Circle()
                    .fill(.background)
                    .overlay {
                        Circle()
                            .fill(tint)
                            .opacity(status == .visited ? 1 : 0)
                    }
                    .shadow(radius: 1.5, y: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        tint,
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: status == .planned ? [3, 3] : []
                        )
                    )
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var label = "\(place.name) \(place.designation), \(place.statesDescription)"
        switch status {
        case .visited: label += ", visited"
        case .planned: label += ", planned"
        case .none: break
        }
        return label
    }
}

/// Alaska, Hawaii and the territories are one tap away (SPECIFICATION.md §5).
struct RegionShortcutBar: View {
    @Binding var camera: MapCameraPosition

    private struct Shortcut: Identifiable {
        let id = UUID()
        let name: String
        let region: MKCoordinateRegion
    }

    private let shortcuts: [Shortcut] = [
        Shortcut(
            name: "Lower 48",
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 32, longitudeDelta: 58)
            )
        ),
        Shortcut(
            name: "Alaska",
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 63.5, longitude: -152),
                span: MKCoordinateSpan(latitudeDelta: 16, longitudeDelta: 40)
            )
        ),
        Shortcut(
            name: "Hawaii",
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20.3, longitude: -156.5),
                span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 6)
            )
        ),
        Shortcut(
            name: "Caribbean",
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 18.3, longitude: -65.5),
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 6)
            )
        ),
        Shortcut(
            name: "Pacific",
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -14.3, longitude: -170.7),
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 6)
            )
        ),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    Button(shortcut.name) {
                        withAnimation(.easeInOut) {
                            camera = .region(shortcut.region)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }
}

extension Coordinate {
    /// The boundary between the domain's own coordinate type and MapKit's.
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension BoundingBox {
    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: centre.clCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(north - south, 0.02),
                longitudeDelta: max(east - west, 0.02)
            )
        )
    }
}

/// `sheet(item:)` over an `Identifiable` optional, which `Place` already is.
extension View {
    func sheet<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        sheet(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: {
                if !$0 {
                    item.wrappedValue = nil
                }
            }
        )) {
            if let value = item.wrappedValue {
                content(value)
            }
        }
    }
}
