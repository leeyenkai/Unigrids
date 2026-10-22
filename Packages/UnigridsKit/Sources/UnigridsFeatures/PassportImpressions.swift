import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The passport's slots, impressions and pages to share (SPECIFICATION.md §9).

/// The commemorative page at the front of the book: every 2026 stamp, with the count.
struct America250Page: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let stamps: [Stamp]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AMERICA 250")
                        .font(UnigridStyle.bandTitle(32))
                        .tracking(2)
                        .foregroundStyle(style.seal)
                    Rectangle()
                        .fill(style.seal)
                        .frame(height: 4)
                    Text(
                        stamps.isEmpty
                            ? "Nothing stamped in 2026 yet."
                            : "\(stamps.count) stamped in 2026."
                    )
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                }
                .padding(.horizontal, 16)

                if stamps.isEmpty {
                    Text(
                        "Any stamp you date in 2026 lands here, including one you back-date "
                            + "for a trip earlier in the year."
                    )
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.inkSecondary)
                    .padding(.horizontal, 16)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 20)],
                        spacing: 24
                    ) {
                        ForEach(stamps.sorted { $0.date > $1.date }) { stamp in
                            if let place = store.place(stamp.place) {
                                VStack(spacing: 8) {
                                    StampView(
                                        face: StampFace(
                                            siteName: place.name,
                                            date: stamp.date,
                                            stateCode: place.states.first?.code ?? "US",
                                            region: place.resolvedPassportRegion,
                                            seed: stamp.seed,
                                            isVerifiedOnSite: stamp.isVerifiedOnSite
                                        ),
                                        diameter: 120
                                    )
                                    .frame(width: 140, height: 140)
                                    Text(place.name)
                                        .font(.custom(
                                            "HelveticaNeue-Medium",
                                            size: 12,
                                            relativeTo: .caption
                                        ))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
        }
        .background(style.page)
        .navigationTitle("America 250")
        .toolbarTitleDisplayMode(.inline)
    }
}

/// One slot on a passport page: a site, or one of its official stamp locations.
struct PassportSlot: Identifiable, Hashable {
    let place: Place
    let location: PointOfInterest?

    var id: String {
        place.id.rawValue + "|" + (location?.id.rawValue ?? "")
    }
}

/// Every impression in a slot, latest first, each with its date, place and verification,
/// the paper-stamp switch collectors use, and a way to delete it — undoably.
struct ImpressionsSheet: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Query private var stamps: [Stamp]

    let slot: PassportSlot
    let region: PassportRegion
    let onStampAgain: () -> Void

    private var impressions: [Stamp] {
        stamps
            .filter { $0.place == slot.place.id }
            .filter {
                slot.location == nil || $0.stampLocation == slot.location?.id || $0
                    .stampLocation == nil
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(impressions) { stamp in
                    ImpressionRow(stamp: stamp, place: slot.place, region: region)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(stamp)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Delete impression", role: .destructive) { delete(stamp) }
                        }
                }
                Button(action: onStampAgain) {
                    Label { Text("Stamp again") } icon: { StampIcon() }
                }
                .buttonStyle(BrochureButtonStyle(.primary))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .paperPage()
            .navigationTitle(slot.location?.name ?? slot.place.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if impressions.isEmpty {
                    ContentUnavailableView("No impressions", systemImage: "seal")
                }
            }
        }
        .sheetSize(width: 520, height: 640)
    }

    private func delete(_ stamp: Stamp) {
        guard let record = try? LogStore(context: context).delete(stamp: stamp) else { return }
        undo?.offer(record, message: record.summary { store.place($0)?.name })
    }
}

/// One impression, large, with what it records.
private struct ImpressionRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Bindable var stamp: Stamp
    let place: Place
    let region: PassportRegion

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            StampView(
                face: StampFace(
                    siteName: place.name,
                    date: stamp.date,
                    stateCode: place.states.first?.code ?? "US",
                    region: region,
                    seed: stamp.seed,
                    isVerifiedOnSite: stamp.isVerifiedOnSite
                ),
                diameter: 104
            )
            .frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 6) {
                Text(stamp.date.formatted(date: .long, time: .omitted))
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                if stamp.isVerifiedOnSite {
                    Label("Stamped on site", systemImage: UnigridsSymbol.verified.systemName)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.ink)
                }
                if stamp.hasAmerica250Seal() {
                    Text("AMERICA 250")
                        .font(UnigridStyle.dataLabel)
                        .tracking(1.2)
                        .foregroundStyle(style.seal)
                }
                Toggle("Paper stamp collected", isOn: Binding(
                    get: { stamp.realStampCollected },
                    set: { value in
                        _ = try? LogStore(context: context)
                            .update { stamp.realStampCollected = value }
                    }
                ))
                .font(UnigridStyle.rowDetail)
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A passport page as an image: the region's band, the count, and recent impressions.
struct PassportPageCard: View {
    @Environment(\.unigrid) private var style
    let region: PassportRegion
    let faces: [StampFace]
    let stamped: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(region.name)
                    .font(UnigridStyle.bandTitle(30))
                    .foregroundStyle(style.bandInk)
                Text("\(stamped) OF \(total) NPS SITES STAMPED")
                    .font(UnigridStyle.dataLabel)
                    .tracking(1.2)
                    .foregroundStyle(style.bandInkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(style.band)
            Rectangle().fill(style.regionInk(region)).frame(height: 6)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(118), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                    StampView(face: face, diameter: 108)
                        .frame(width: 118, height: 118)
                }
            }
            .padding(20)
            Text("UNIGRIDS PASSPORT")
                .font(UnigridStyle.dataLabel)
                .tracking(1.4)
                .foregroundStyle(style.inkSecondary)
                .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 552)
        .background(style.page)
    }
}
