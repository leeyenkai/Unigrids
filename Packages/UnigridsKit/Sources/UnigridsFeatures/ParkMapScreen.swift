import MapKit
import Network
import Observation
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The Park map (SPECIFICATION.md §8): a park's offline topographic map with its trails
/// and sights, which works with no connection at all — opened from the guide, a trail's
/// page, or in place of the 3D explorer when the device is offline.
struct ParkMapScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkStatus.self) private var network: NetworkStatus?

    let place: Place
    let pack: OfflinePack
    var focusTrail: UnigridsID?

    @State private var showsUserLocation = false
    @State private var locating = false
    @State private var camera: AtlasCameraRequest?
    @State private var problem: LocationProblem?

    var body: some View {
        NavigationStack {
            ParkTileMapView(
                pack: pack,
                trails: store.trails(in: place.id),
                sights: store.sights(in: place.id),
                facilities: store.pointsOfInterest(in: place.id)
                    .filter { $0.kind == .visitorCentre || $0.kind == .campground },
                focusTrail: focusTrail,
                showsUserLocation: showsUserLocation,
                inks: ParkTileMapView.Inks(
                    trail: PlatformColor(style.trail),
                    focus: PlatformColor(style.ink),
                    marker: PlatformColor(style.band)
                ),
                camera: camera
            )
            .ignoresSafeArea(edges: [.bottom, .horizontal])
            .safeAreaInset(edge: .top, spacing: 0) {
                BandHeader(
                    "Park map",
                    kicker: place.name + (network?.isOnline == false
                        ? " · No connection — this map works offline" : " · Works offline"),
                    compact: true
                )
            }
            .overlay(alignment: .bottomLeading) {
                Text(pack.attribution)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(style.page.opacity(0.88))
                    .padding(.leading, 8)
                    .padding(.bottom, 28)
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem {
                    Button {
                        Task { await locate() }
                    } label: {
                        Label("Where am I", symbol: showsUserLocation ? .located : .locate)
                    }
                    .disabled(locating)
                    .help("Where am I")
                }
            }
            .alert(
                problem?.title ?? "",
                isPresented: Binding(get: { problem != nil }, set: {
                    if !$0 {
                        problem = nil
                    }
                }),
                presenting: problem
            ) { problem in
                if let settings = problem.settingsURL {
                    Button("Open Settings") { AppServices.openExternally(settings) }
                }
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
            }
        }
    }

    /// Show the reader on the map, and go there if they are inside the pack. The position
    /// is used on the device and never stored (§15).
    private func locate() async {
        locating = true
        defer { locating = false }
        guard let here = await OnSiteCheck().currentCoordinate() else {
            problem = OnSiteCheck.isRefused ? .refused : .unavailable
            return
        }
        showsUserLocation = true
        if pack.rendered.contains(here) {
            let pad = 0.01
            camera = AtlasCameraRequest(box: BoundingBox(
                south: here.latitude - pad, west: here.longitude - pad,
                north: here.latitude + pad, east: here.longitude + pad
            ))
        }
    }
}

extension View {
    /// Present a park's offline map: full screen on iPhone and iPad, a large sheet on the Mac.
    func parkMap(
        isPresented: Binding<Bool>,
        place: Place,
        focusTrail: UnigridsID? = nil
    ) -> some View {
        modifier(ParkMapPresenter(isPresented: isPresented, place: place, focusTrail: focusTrail))
    }
}

private struct ParkMapPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let place: Place
    let focusTrail: UnigridsID?

    func body(content: Content) -> some View {
        if let pack = OfflinePackCatalogue.bundled.pack(for: place.id) {
            #if os(iOS)
                content.fullScreenCover(isPresented: $isPresented) {
                    ParkMapScreen(place: place, pack: pack, focusTrail: focusTrail)
                        .unigridsServices()
                        .undoHost()
                }
            #else
                content.unigridsSheet(isPresented: $isPresented) {
                    ParkMapScreen(place: place, pack: pack, focusTrail: focusTrail)
                        .frame(minWidth: 900, minHeight: 640)
                }
            #endif
        } else {
            content
        }
    }
}

/// Whether the device has a usable connection, watched for the whole app: the 3D explorer
/// gives way to the Park map without one.
@MainActor
@Observable
public final class NetworkStatus {
    public private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "unigrids.network", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
