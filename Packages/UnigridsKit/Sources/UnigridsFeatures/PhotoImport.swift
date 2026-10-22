import Photos
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Photo import (SPECIFICATION.md §9): the photo library read on this device for where
/// and when each photo was taken, matched to the places' outlines, and offered back as
/// visits and trips to accept or leave. Nothing is logged until the reader says so, and
/// what is logged keeps photo references, never copies.
struct PhotoImportScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Query private var visits: [Visit]

    private enum Phase {
        case asking
        case denied
        case scanning
        case ready([ProposedTrip])
        case imported(Int)
    }

    @State private var phase = Phase.asking
    @State private var excluded: Set<String> = []
    @State private var groupIntoTrips = true
    @State private var alsoStamp = false
    @State private var scanned = 0

    var body: some View {
        NavigationStack {
            content
                .background(style.page)
                .navigationTitle("Import from Photos")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if case let .ready(trips) = phase, !trips.isEmpty {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import \(selectedCount(trips))") { importSelected(trips) }
                                .disabled(selectedCount(trips) == 0)
                        }
                    }
                }
                .task { await start() }
        }
        .sheetSize(width: 560, height: 720)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .asking:
            ProgressView("Asking for access to your photos")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            ContentUnavailableView {
                Label("No access to Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(
                    "Unigrids reads only the date and place of each photo, on this device. "
                        + "Allow access in Settings to find visits you have not logged."
                )
            }
        case .scanning:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading \(scanned.formatted()) photos on this device")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(trips) where trips.isEmpty:
            ContentUnavailableView(
                "Nothing new to import",
                systemImage: "checkmark.circle",
                description: Text(
                    "None of your geotagged photos were taken in a place you have not already "
                        + "logged on that day."
                )
            )
        case let .ready(trips):
            proposals(trips)
        case let .imported(count):
            ContentUnavailableView(
                "\(count) visit\(count == 1 ? "" : "s") added",
                systemImage: "checkmark.circle.fill",
                description: Text("They are in Trips, marked as from your photos.")
            )
        }
    }

    private func proposals(_ trips: [ProposedTrip]) -> some View {
        List {
            Section {
                Toggle("Group into trips", isOn: $groupIntoTrips)
                Toggle(isOn: $alsoStamp) {
                    Label { Text("Stamp the passport too") } icon: { StampIcon() }
                }
            } footer: {
                Text(
                    "Untick anything you do not want. Photos stay in your library; the log "
                        + "keeps a reference to them."
                )
                .font(UnigridStyle.caption)
            }
            ForEach(trips) { trip in
                Section {
                    ForEach(trip.visits) { visit in
                        ProposedVisitRow(
                            visit: visit,
                            place: store.place(visit.placeID),
                            isOn: Binding(
                                get: { !excluded.contains(visit.id) },
                                set: { isOn in
                                    if isOn {
                                        excluded.remove(visit.id)
                                    } else {
                                        excluded.insert(visit.id)
                                    }
                                }
                            )
                        )
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHead(tripName(trip), detail: "\(trip.visits.count)")
                }
            }
        }
        .listStyle(.plain)
        .paperPage()
    }

    private func selectedCount(_ trips: [ProposedTrip]) -> Int {
        trips.flatMap(\.visits).count { !excluded.contains($0.id) }
    }

    private func tripName(_ trip: ProposedTrip) -> String {
        let states = trip.visits.compactMap { store.place($0.placeID)?.states.first?.name }
        let main = Dictionary(grouping: states, by: \.self).max { $0.value.count < $1.value.count }?
            .key
        let when = trip.start.formatted(.dateTime.month(.wide).year())
        return [main, when].compactMap(\.self).joined(separator: ", ")
    }

    // MARK: Scanning

    private func start() async {
        guard case .asking = phase else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            phase = .denied
            return
        }
        phase = .scanning
        let photos = await Self.geotaggedPhotos { count in
            Task { @MainActor in scanned = count }
        }
        let locator = PlaceLocator(boundaries: store.boundaries)
        let logged = Set(visits.map {
            PhotoVisits.loggedKey($0.place, Calendar.current.startOfDay(for: $0.date))
        })
        let proposed = await Task.detached(priority: .userInitiated) {
            PhotoVisits.propose(photos: photos, locator: locator, alreadyLogged: logged)
        }.value
        phase = .ready(PhotoVisits.trips(from: proposed))
    }

    /// Every photo with a location, read off the library's metadata. Only the date and
    /// the coordinate are read: no image is opened here.
    private static func geotaggedPhotos(
        progress: @escaping @Sendable (Int) -> Void
    ) async -> [GeoPhoto] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var photos: [GeoPhoto] = []
            photos.reserveCapacity(assets.count / 2)
            assets.enumerateObjects { asset, index, _ in
                if let location = asset.location, let date = asset.creationDate {
                    photos.append(GeoPhoto(
                        id: asset.localIdentifier,
                        date: date,
                        location: Coordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    ))
                }
                if index.isMultiple(of: 500) {
                    progress(index)
                }
            }
            return photos
        }.value
    }

    // MARK: Importing

    private func importSelected(_ trips: [ProposedTrip]) {
        let log = LogStore(context: context)
        var count = 0
        for proposed in trips {
            let chosen = proposed.visits.filter { !excluded.contains($0.id) }
            guard !chosen.isEmpty else { continue }
            var trip: Trip?
            if groupIntoTrips, chosen.count > 1 {
                trip = try? log.createTrip(
                    name: tripName(proposed),
                    startDate: chosen.first?.day,
                    endDate: chosen.last?.day,
                    status: .done
                )
            }
            for visit in chosen {
                guard let logged = try? log.checkIn(
                    to: visit.placeID,
                    on: visit.first,
                    source: .photoImport,
                    trip: trip
                ) else { continue }
                if let checkIn = try? log.checkIn(
                    at: .place(visit.placeID),
                    during: logged,
                    on: visit.first
                ) {
                    _ = try? log.update {
                        checkIn.photoAssetIdentifiers = Array(visit.photoIDs.prefix(50))
                    }
                }
                if alsoStamp {
                    _ = try? log.stamp(visit.placeID, on: visit.first)
                }
                count += 1
            }
        }
        phase = .imported(count)
    }
}

/// One suggested visit: a thumbnail from the first photo, the place, the day.
private struct ProposedVisitRow: View {
    @Environment(\.unigrid) private var style
    let visit: ProposedVisit
    let place: Place?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                PhotoThumbnail(identifier: visit.photoIDs.first)
                    .frame(width: 54, height: 54)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(place?.name ?? "Unknown place")
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                    Text(
                        "\(visit.day.formatted(date: .abbreviated, time: .omitted)) · "
                            + "\(visit.photoIDs.count) photo\(visit.photoIDs.count == 1 ? "" : "s")"
                    )
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                }
            }
        }
    }
}

/// A small thumbnail of a library photo, drawn from PhotoKit on demand and never stored.
struct PhotoThumbnail: View {
    @Environment(\.unigrid) private var style
    let identifier: String?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(style.rule)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(style.inkSecondary)
                    }
            }
        }
        .task(id: identifier) {
            guard let identifier else { return }
            image = await Self.load(identifier)
        }
        .accessibilityHidden(true)
    }

    private static func load(_ identifier: String) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            .firstObject
        else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !resumed, !degraded || image == nil else { return }
                resumed = true
                #if os(iOS)
                    continuation.resume(returning: image?.cgImage)
                #else
                    continuation.resume(returning: image?.cgImage(
                        forProposedRect: nil,
                        context: nil,
                        hints: nil
                    ))
                #endif
            }
        }
    }
}
