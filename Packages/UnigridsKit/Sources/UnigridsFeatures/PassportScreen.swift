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
/// page carrying a stamped-so-far count, then a slot for every NPS site — national parks
/// first — where an empty slot stays a faint outline so the gaps show what is left. State
/// parks and other agencies' sites follow under "Beyond the NPS", in the order stamped.
public struct PassportScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query private var stamps: [Stamp]

    public init() {}

    private var stampedPlaceIDs: Set<UnigridsID> {
        Set(stamps.map(\.place))
    }

    private var stampsIn2026: [Stamp] {
        stamps.filter { $0.hasAmerica250Seal() }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    BandHeader(
                        "Passport",
                        kicker: "\(stamps.count) stamp\(stamps.count == 1 ? "" : "s") · "
                            + "\(stampedPlaceIDs.count) "
                            + (stampedPlaceIDs.count == 1 ? "place" : "places")
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        America250Page(stamps: stampsIn2026)
                    } label: {
                        America250Row(stampCount: stampsIn2026.count)
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHead("Commemorative")
                } footer: {
                    Text(
                        "Every stamp dated in 2026 — the 250th anniversary year — carries "
                            + "the America 250 seal, and is gathered on this page."
                    )
                    .font(UnigridStyle.caption)
                }

                Section {
                    ForEach(PassportRegion.allCases) { region in
                        NavigationLink {
                            PassportRegionPage(region: region)
                        } label: {
                            RegionRow(region: region, completion: completion(for: region))
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHead("Regions", detail: "NPS sites stamped")
                } footer: {
                    Text(
                        "Regions follow the paper passport's nine. Sites outside the NPS go by "
                            + "their state, and appear on a region's page once stamped."
                    )
                    .font(UnigridStyle.caption)
                }
            }
            .listStyle(.plain)
            .paperPage()
            .navigationTitle("Passport")
            .toolbarTitleDisplayMode(.inline)
        }
    }

    /// Progress through a region's NPS sites — the slots the paper book prints.
    private func completion(for region: PassportRegion) -> Completion {
        let places = (store.placesByPassportRegion()[region] ?? []).filter { $0.agency == .nps }
        let stamped = places.count { stampedPlaceIDs.contains($0.id) }
        return Completion(visited: stamped, total: places.count)
    }
}

struct RegionRow: View {
    @Environment(\.unigrid) private var style

    let region: PassportRegion
    let completion: Completion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(style.regionInk(region))
                    .frame(width: 14, height: 14)
                Text(region.name)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Spacer()
                Text(completion.description)
                    .font(UnigridStyle.dataLabel)
                    .monospacedDigit()
                    .foregroundStyle(style.inkSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(style.rule)
                    Rectangle()
                        .fill(style.regionInk(region))
                        .frame(width: proxy.size.width * completion.fraction)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(region.name), \(completion.description) NPS sites stamped")
    }
}

struct America250Row: View {
    @Environment(\.unigrid) private var style
    let stampCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("250")
                .font(.custom("HelveticaNeue-Bold", size: 13))
                .foregroundStyle(style.seal)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .overlay { Rectangle().strokeBorder(style.seal, lineWidth: 1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text("America 250")
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Text(stampCount == 0 ? "No 2026 stamps yet" : "\(stampCount) stamped in 2026")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A region's pages: the title page, then a slot per NPS site, then whatever beyond the
/// NPS has been stamped here.
struct PassportRegionPage: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style

    let region: PassportRegion

    @Query private var stamps: [Stamp]
    @State private var stamping: Place?

    private var places: [Place] {
        store.placesByPassportRegion()[region] ?? []
    }

    private var stampsByPlace: [UnigridsID: [Stamp]] {
        Dictionary(grouping: stamps, by: \.place)
    }

    var body: some View {
        let parks = places.filter { $0.tier == .nationalPark }
        let units = places.filter { $0.tier == .npsUnit }
        let beyond = places
            .filter { $0.agency != .nps && stampsByPlace[$0.id]?.isEmpty == false }
            .sorted { first($0) < first($1) }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titlePage(npsSites: parks + units)
                slotSection("National parks", places: parks)
                slotSection("Other NPS sites", places: units)
                if !beyond.isEmpty {
                    slotSection("Beyond the NPS", places: beyond)
                }
            }
            .padding(.vertical, 20)
        }
        .background(style.page)
        .navigationTitle(region.name)
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $stamping) { place in
            StampSheet(place: place)
        }
    }

    private func first(_ place: Place) -> Date {
        stampsByPlace[place.id]?.map(\.date).min() ?? .distantFuture
    }

    private func titlePage(npsSites: [Place]) -> some View {
        let stamped = npsSites.count { stampsByPlace[$0.id]?.isEmpty == false }
        return VStack(alignment: .leading, spacing: 10) {
            Text(region.name)
                .font(UnigridStyle.bandTitle(32))
                .foregroundStyle(style.regionInk(region))
            Rectangle()
                .fill(style.regionInk(region))
                .frame(height: 4)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(stamped)")
                    .font(UnigridStyle.figure)
                    .foregroundStyle(style.ink)
                    .monospacedDigit()
                Text("of \(npsSites.count) NPS sites stamped")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func slotSection(_ title: String, places: [Place]) -> some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHead(title, detail: "\(places.count)")
                    .padding(.horizontal, 16)
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
        }
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
                .font(.custom("HelveticaNeue-Medium", size: 12, relativeTo: .caption))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if placeStamps.count > 1 {
                Text("\(placeStamps.count) impressions")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
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
