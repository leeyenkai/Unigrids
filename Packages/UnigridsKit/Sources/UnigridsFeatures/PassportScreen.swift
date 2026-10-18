import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The passport: a digital stamp book in the style of the paper NPS passport
/// (SPECIFICATION.md §9).
///
/// Nine colour-coded regions, each stamping in its own ink. A region opens with a title
/// page carrying a stamped-so-far count, then the site pages, where an empty slot stays a
/// faint outline so the gaps show what is left.
public struct PassportScreen: View {
    @Environment(\.referenceStore) private var store
    @Query private var stamps: [Stamp]

    public init() {}

    private var stampsByPlace: [UnigridsID: [Stamp]] {
        Dictionary(grouping: stamps, by: \.place)
    }

    private var regions: [PassportRegion] {
        let grouped = store.placesByPassportRegion()
        return PassportRegion.allCases.filter { grouped[$0]?.isEmpty == false }
    }

    private var stampsIn2026: [Stamp] {
        stamps.filter { $0.hasAmerica250Seal() }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        America250Page(stamps: stampsIn2026)
                    } label: {
                        America250Row(stampCount: stampsIn2026.count)
                    }
                } header: {
                    Text("Commemorative")
                } footer: {
                    Text(
                        "Every stamp dated in 2026 — the 250th anniversary year — carries "
                            + "the America 250 seal, and is gathered on this page."
                    )
                }

                Section("Regions") {
                    ForEach(regions) { region in
                        NavigationLink {
                            PassportRegionPage(region: region)
                        } label: {
                            RegionRow(
                                region: region,
                                completion: completion(for: region)
                            )
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "Beyond the NPS arrives with tiers 2 to 4",
                            systemImage: "map"
                        )
                        .font(.subheadline.weight(.medium))
                        Text(
                            "State parks and major federal sites get their own section per "
                                + "region once the data pipeline adds them."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Passport")
        }
    }

    private func completion(for region: PassportRegion) -> Completion {
        let places = store.placesByPassportRegion()[region] ?? []
        let stamped = places.count { stampsByPlace[$0.id]?.isEmpty == false }
        return Completion(visited: stamped, total: places.count)
    }
}

struct RegionRow: View {
    @Environment(\.unigrid) private var style

    let region: PassportRegion
    let completion: Completion

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(style.regionInk(region))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(region.name)
                    .font(.body.weight(.medium))
                Text("\(completion.description) stamped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: completion.fraction)
                .progressViewStyle(.linear)
                .frame(width: 60)
                .tint(style.regionInk(region))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.name), \(completion.description) stamped")
    }
}

struct America250Row: View {
    @Environment(\.unigrid) private var style
    let stampCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "seal.fill")
                .foregroundStyle(style.seal)
            VStack(alignment: .leading, spacing: 2) {
                Text("America 250")
                    .font(.body.weight(.medium))
                Text(stampCount == 0 ? "No 2026 stamps yet" : "\(stampCount) in 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A region's pages: the title page's count, then one slot per site.
struct PassportRegionPage: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style

    let region: PassportRegion

    @Query private var stamps: [Stamp]
    @State private var stamping: Place?
    @State private var viewing: Stamp?

    private var places: [Place] {
        store.placesByPassportRegion()[region] ?? []
    }

    private var stampsByPlace: [UnigridsID: [Stamp]] {
        Dictionary(grouping: stamps, by: \.place)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titlePage

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 20)],
                    spacing: 24
                ) {
                    ForEach(places) { place in
                        slot(for: place)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 20)
        }
        .navigationTitle(region.name)
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $stamping) { place in
            StampSheet(place: place)
        }
    }

    private var titlePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(region.name.uppercased())
                .font(.title2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(style.regionInk(region))
            Rectangle()
                .fill(style.regionInk(region))
                .frame(height: 3)
            let stamped = places.count { stampsByPlace[$0.id]?.isEmpty == false }
            Text("\(stamped) of \(places.count) sites stamped")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func slot(for place: Place) -> some View {
        let placeStamps = (stampsByPlace[place.id] ?? []).sorted { $0.date > $1.date }
        VStack(spacing: 8) {
            if let latest = placeStamps.first {
                ZStack {
                    // A later visit adds a new impression that overlaps the old one, like
                    // a well-used paper page.
                    ForEach(placeStamps.dropFirst().prefix(2).reversed()) { older in
                        StampView(face: face(for: older, place: place), diameter: 120)
                            .opacity(0.35)
                    }
                    StampView(face: face(for: latest, place: place), diameter: 120)
                }
                .frame(width: 140, height: 140)
            } else {
                Button {
                    stamping = place
                } label: {
                    StampSlotView(siteName: place.name, diameter: 120)
                        .frame(width: 140, height: 140)
                }
                .buttonStyle(.plain)
            }

            Text(place.name)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if placeStamps.count > 1 {
                Text("\(placeStamps.count) impressions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Stamp again") { stamping = place }
        }
    }

    private func face(for stamp: Stamp, place: Place) -> StampFace {
        StampFace(
            siteName: stampLocationName(stamp, place: place),
            date: stamp.date,
            stateCode: place.states.first?.code ?? "US",
            region: region,
            seed: stamp.seed,
            isVerifiedOnSite: stamp.isVerifiedOnSite
        )
    }

    /// A site with several official stamp locations gets one slot per location, and the
    /// impression names the location rather than the park.
    private func stampLocationName(_ stamp: Stamp, place: Place) -> String {
        guard let locationID = stamp.stampLocation,
              let location = store.pointsOfInterest(in: place.id)
              .first(where: { $0.id == locationID })
        else { return place.name }
        return location.name
    }
}

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
                        .font(.title2.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(style.seal)
                    Rectangle()
                        .fill(style.seal)
                        .frame(height: 3)
                    Text(
                        stamps.isEmpty
                            ? "Nothing stamped in 2026 yet."
                            : "\(stamps.count) stamped in 2026."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                if stamps.isEmpty {
                    ContentUnavailableView {
                        Label("No 2026 stamps", systemImage: "seal")
                    } description: {
                        Text(
                            "Any stamp you date in 2026 lands here, including one you "
                                + "back-date for a trip earlier in the year."
                        )
                    }
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
                                        .font(.caption.weight(.medium))
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
        .navigationTitle("America 250")
        .toolbarTitleDisplayMode(.inline)
    }
}
