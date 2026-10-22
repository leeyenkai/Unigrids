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
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Query private var visits: [Visit]

    private enum Phase {
        case asking
        case denied
        case reading
        case matching
        case ready([ProposedTrip])
        case imported(Int)
    }

    @State private var phase = Phase.asking
    @State private var excluded: Set<String> = []
    @State private var groupIntoTrips = true
    @State private var alsoStamp = false
    @State private var scanned = 0
    @State private var total = 0
    @State private var failures = 0

    var body: some View {
        SheetPage(
            "Import from Photos",
            kicker: "Visits your photos remember",
            actions: actions,
            width: 560,
            height: 720
        ) {
            content
        }
        .task { await start() }
    }

    private var actions: SheetActions {
        switch phase {
        case let .ready(trips) where !trips.isEmpty:
            let count = selectedCount(trips)
            return .confirm(
                "Import \(count)",
                enabled: count > 0,
                cancel: { dismiss() },
                action: { importSelected(trips) }
            )
        case .imported:
            return .done { dismiss() }
        default:
            return .cancel { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .asking:
            ProgressView("Asking for access to your photos")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            ContentUnavailableView {
                Label("No access to Photos", symbol: .importPhotos)
            } description: {
                Text(
                    "Unigrids reads only the date and place of each photo, on this device. "
                        + "Allow access in Settings to find visits you have not logged."
                )
            } actions: {
                if let settings = Self.settingsURL {
                    Button("Open Settings") { AppServices.openExternally(settings) }
                        .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                }
            }
        case .reading:
            VStack(spacing: 12) {
                ProgressView(value: Double(scanned), total: Double(max(total, 1)))
                    .frame(maxWidth: 280)
                Text("Read \(scanned.formatted()) of \(total.formatted()) photos on this device")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .matching:
            ProgressView("Matching photos to places")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(trips) where trips.isEmpty:
            ContentUnavailableView(
                "Nothing new to import",
                systemImage: UnigridsSymbol.visited.systemName,
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
                systemImage: UnigridsSymbol.visited.systemName,
                description: Text(
                    "They are in Trips, marked as from your photos."
                        + (failures > 0 ? " \(failures) could not be saved." : "")
                )
            )
        }
    }

    private static var settingsURL: URL? {
        #if os(iOS)
            URL(string: UIApplication.openSettingsURLString)
        #else
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
        #endif
    }

    private func proposals(_ trips: [ProposedTrip]) -> some View {
        List {
            Section {
                Toggle("Group into trips", isOn: $groupIntoTrips)
                Toggle(isOn: $alsoStamp) {
                    Label { Text("Stamp the passport too") } icon: { StampIcon() }
                }
                ListNotes {
                    FormNote(
                        "Untick anything you do not want. Photos stay in your library; the log "
                            + "keeps a reference to them."
                    )
                }
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
    }

    private func selectedCount(_ trips: [ProposedTrip]) -> Int {
        trips.flatMap(\.visits).count { !excluded.contains($0.id) }
    }

    private func tripName(_ trip: ProposedTrip) -> String {
        let states = trip.visits.compactMap { store.place($0.placeID)?.states.first?.name }
        let main = Dictionary(grouping: states, by: \.self).max { $0.value.count < $1.value.count }?
            .key
        let when = trip.start.formatted(UnigridsFormat.month())
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
        phase = .reading
        let photos = await Self.geotaggedPhotos { count, total in
            Task { @MainActor in
                scanned = count
                self.total = total
            }
        }
        phase = .matching
        let store = store
        let locator = PlaceLocator(boundaries: store.boundaries)
        // Days at each place, so a visit already logged is matched on the same day the
        // proposal is reckoned in.
        let logged = Set(visits.map {
            PhotoVisits.loggedKey(
                $0.place,
                UnigridsCalendar.gregorian(at: store.place($0.place)).startOfDay(for: $0.date)
            )
        })
        let proposed = await Task.detached(priority: .userInitiated) {
            PhotoVisits.propose(
                photos: photos,
                locator: locator,
                alreadyLogged: logged,
                calendarAt: { UnigridsCalendar.gregorian(at: store.place($0)) }
            )
        }.value
        phase = .ready(PhotoVisits.trips(from: proposed))
    }

    /// Every photo with a location, read off the library's metadata. Only the date and
    /// the coordinate are read: no image is opened here.
    private static func geotaggedPhotos(
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> [GeoPhoto] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            let total = assets.count
            progress(0, total)
            var photos: [GeoPhoto] = []
            photos.reserveCapacity(total / 2)
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
                if index.isMultiple(of: 250) {
                    progress(index, total)
                }
            }
            progress(total, total)
            return photos
        }.value
    }

    // MARK: Importing

    /// Log what was ticked, and offer to take the whole import back in one undo.
    private func importSelected(_ trips: [ProposedTrip]) {
        let log = LogStore(context: context)
        var made = RecordIDs()
        var count = 0
        var failed = 0
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
                if let trip {
                    made.trips.append(trip.id)
                }
            }
            for visit in chosen {
                do {
                    try record(visit, trip: trip, log: log, into: &made)
                    count += 1
                } catch {
                    failed += 1
                }
            }
        }
        failures = failed
        phase = .imported(count)
        if count > 0 {
            let change = UndoableChange(
                subject: .imported(
                    visits: made.visits.count, trips: made.trips.count, stamps: made.stamps.count
                ),
                takeOut: made
            )
            undo?.offer(change, message: change.summary { _ in nil })
        }
    }

    private func record(
        _ visit: ProposedVisit,
        trip: Trip?,
        log: LogStore,
        into made: inout RecordIDs
    ) throws {
        let calendar = UnigridsCalendar.gregorian(at: store.place(visit.placeID))
        let existing = try log.visit(to: visit.placeID, on: visit.first, calendar: calendar)
        let logged = try log.checkIn(
            to: visit.placeID,
            on: visit.first,
            source: .photoImport,
            trip: trip,
            calendar: calendar
        )
        if existing == nil {
            made.visits.append(logged.id)
        }
        let checkIn = try log.checkIn(at: .place(visit.placeID), during: logged, on: visit.first)
        made.checkIns.append(checkIn.id)
        try log.update { checkIn.photoAssetIdentifiers = Array(visit.photoIDs.prefix(50)) }
        if alsoStamp {
            let stamp = try log.stamp(visit.placeID, on: visit.first, calendar: calendar)
            made.stamps.append(stamp.id)
        }
    }
}

/// One suggested visit: a thumbnail from the first photo, the place, the day.
private struct ProposedVisitRow: View {
    @Environment(\.unigrid) private var style
    let visit: ProposedVisit
    let place: Place?
    @Binding var isOn: Bool

    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

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
                        "\(visit.day.formatted(UnigridsFormat.day(in: calendar))) · "
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
                        Image(.photo)
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
