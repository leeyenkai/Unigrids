import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The passport: a digital stamp book in the style of the paper NPS passport
/// (SPECIFICATION.md §9), one book per country with parks in the data (ADR 0013).
///
/// The US book's nine colour-coded regions, each stamping in its own ink; Japan's eight
/// and Norway's six are Unigrids' own. A region opens with a title
/// page carrying a stamped-so-far count, then a slot for every NPS site — national parks
/// first — where an empty slot stays a faint outline so the gaps show what is left. State
/// parks and other agencies' sites follow under "Beyond the NPS", in the order stamped.
public struct PassportScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query private var stamps: [Stamp]

    public init() {}

    /// The book open, kept per device.
    @AppStorage("passport.book") private var bookCode = Country.unitedStates.rawValue

    private var book: Country {
        let books = store.passportBooks
        return Country(rawValue: bookCode).flatMap { books.contains($0) ? $0 : nil }
            ?? .unitedStates
    }

    private var stampedPlaceIDs: Set<UnigridsID> {
        Set(stamps.map(\.place))
    }

    /// The sealed stamps the page can show: one whose place has left the data is not on
    /// the page, so it is not in the count either.
    private var stampsIn2026: [Stamp] {
        stamps.filter { stamp in
            store.place(stamp.place).map { stamp.hasAmerica250Seal(at: $0) } ?? false
        }
    }

    @State private var path = NavigationPath()

    public var body: some View {
        NavigationStack(path: $path) {
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

                if store.passportBooks.count > 1 {
                    Section {
                        Picker("Book", selection: $bookCode) {
                            ForEach(store.passportBooks) { country in
                                Text(country.name).tag(country.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }

                if book == .unitedStates {
                    commemorative
                }

                Section {
                    ForEach(PassportRegion.regions(in: book)) { region in
                        NavigationLink {
                            PassportRegionPage(region: region)
                        } label: {
                            RegionRow(region: region, completion: completion(for: region))
                        }
                        .listRowBackground(Color.clear)
                    }
                    ListNotes {
                        Text(book.passportRegionsNote)
                            .font(UnigridStyle.caption)
                    }
                } header: {
                    SectionHead("Regions", detail: "\(book.passportSlotNoun.capitalized) stamped")
                }

                UnknownPlaceStamps(stamps: stamps.filter { store.place($0.place) == nil })
            }
            .listStyle(.plain)
            .paperPage()
            .navigationTitle("Passport")
            .toolbarTitleDisplayMode(.inline)
            #if os(iOS)
                .toolbar { SettingsToolbarItem() }
            #endif
                .navigationDestination(for: PassportRegion.self) { region in
                    PassportRegionPage(region: region)
                }
                .onAppear {
                    let region = DebugLaunch.passportRegion.flatMap(PassportRegion.init(rawValue:))
                    if path.isEmpty, let region {
                        bookCode = region.country.rawValue
                        path.append(region)
                    }
                }
        }
    }

    /// The America 250 page: the US book's alone.
    private var commemorative: some View {
        Section {
            NavigationLink {
                America250Page(stamps: stampsIn2026)
            } label: {
                America250Row(stampCount: stampsIn2026.count)
            }
            .listRowBackground(Color.clear)
            ListNotes {
                Text(
                    "Every stamp dated in 2026 — the 250th anniversary year — carries "
                        + "the America 250 seal, and is gathered on this page."
                )
                .font(UnigridStyle.caption)
            }
        } header: {
            SectionHead("Commemorative")
        }
    }

    /// Progress through a region's NPS sites — the slots the paper book prints.
    private func completion(for region: PassportRegion) -> Completion {
        let places = (store.placesByPassportRegion()[region] ?? [])
            .filter(\.isNationalParkSystemSite)
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
        .accessibilityLabel(
            "\(region.name), \(completion.description) "
                + "\(region.country.passportSlotNoun) stamped"
        )
    }
}

struct America250Row: View {
    @Environment(\.unigrid) private var style
    let stampCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("250")
                .font(.custom("HelveticaNeue-Bold", size: 13, relativeTo: .footnote))
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
    @State private var stamping: PassportSlot?
    @State private var viewing: PassportSlot?
    @State private var stampAfterViewing: PassportSlot?
    @State private var pageImage: URL?

    private var places: [Place] {
        store.placesByPassportRegion()[region] ?? []
    }

    /// The stamps by place, built once per redraw and handed down: built per slot and per
    /// sort comparison, a region of a thousand places with a long log stalled the page.
    private var stampsByPlace: [UnigridsID: [Stamp]] {
        Dictionary(grouping: stamps, by: \.place)
    }

    var body: some View {
        let byPlace = stampsByPlace
        let parks = places.filter { $0.tier == .nationalPark }
        let units = places.filter { $0.tier == .npsUnit }
        let firsts = byPlace.mapValues { $0.map(\.date).min() ?? .distantFuture }
        let beyond = places
            .filter { !$0.isNationalParkSystemSite && byPlace[$0.id]?.isEmpty == false }
            .sorted { (firsts[$0.id] ?? .distantFuture) < (firsts[$1.id] ?? .distantFuture) }
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titlePage(npsSites: parks + units, byPlace: byPlace)
                slotSection("National parks", places: parks, byPlace: byPlace)
                slotSection("Other NPS sites", places: units, byPlace: byPlace)
                if !beyond.isEmpty {
                    slotSection(
                        region.country.passportBeyondTitle, places: beyond, byPlace: byPlace
                    )
                }
            }
            .padding(.bottom, 20)
        }
        .background(style.page)
        .navigationTitle(region.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if let pageImage {
                ToolbarItem {
                    ShareLink(item: pageImage) {
                        Label("Share this page", symbol: .share)
                    }
                    .help("Share this page")
                }
            }
        }
        .task(id: stamps.count) { pageImage = renderPage() }
        .unigridsSheet(item: $stamping) { slot in
            StampSheet(place: slot.place, location: slot.location?.id)
        }
        // "Stamp again" closes the impressions and opens the stamp sheet once it has
        // gone: presenting one sheet while another is still leaving is dropped on iOS.
        .unigridsSheet(item: $viewing, onDismiss: {
            if let next = stampAfterViewing {
                stampAfterViewing = nil
                stamping = next
            }
        }) { slot in
            ImpressionsSheet(slot: slot, region: region) {
                stampAfterViewing = slot
                viewing = nil
            }
        }
    }

    /// The page as an image to share (§9: "any page or spread exports as an image"): the
    /// region's band and its most recent impressions.
    private func renderPage() -> URL? {
        let recent = stamps
            .filter { store.place($0.place)?.resolvedPassportRegion == region }
            .sorted { $0.date > $1.date }
            .prefix(16)
        guard !recent.isEmpty else { return nil }
        let faces = recent.compactMap { stamp -> StampFace? in
            guard let place = store.place(stamp.place) else { return nil }
            return StampFace(
                siteName: place.name,
                date: stamp.date,
                stateCode: place.stampMark,
                region: region,
                country: place.country,
                seed: stamp.seed,
                isVerifiedOnSite: stamp.isVerifiedOnSite,

                calendar: UnigridsCalendar.gregorian(at: place),
                localName: place.leadLocalName?.text
            )
        }
        let stampedPlaces = Set(stamps.map(\.place))
        let npsSites = places.filter(\.isNationalParkSystemSite)
        let card = PassportPageCard(
            region: region,
            faces: faces,
            stamped: npsSites.count { stampedPlaces.contains($0.id) },
            total: npsSites.count
        )
        .environment(\.unigrid, style)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Passport - \(region.name).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    private func titlePage(npsSites: [Place], byPlace: [UnigridsID: [Stamp]]) -> some View {
        let stamped = npsSites.count { byPlace[$0.id]?.isEmpty == false }
        return VStack(alignment: .leading, spacing: 0) {
            BandHeader(
                region.name,
                kicker: "\(stamped) of \(npsSites.count) "
                    + "\(region.country.passportSlotNoun) stamped"
            )
            // The region's ink, as the paper passport colours its pages.
            Rectangle()
                .fill(style.regionInk(region))
                .frame(height: 6)
        }
    }

    @ViewBuilder
    private func slotSection(
        _ title: String,
        places: [Place],
        byPlace: [UnigridsID: [Stamp]]
    ) -> some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionHead(title, detail: "\(places.count)")
                    .padding(.horizontal, 16)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 20)],
                    spacing: 24
                ) {
                    ForEach(places.flatMap(slots)) { slot in
                        slotView(
                            slot,
                            stamps: slot.impressions(among: byPlace[slot.place.id] ?? [])
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// A site with several official stamp locations gets one slot per location (§9);
    /// every other site gets one.
    private func slots(for place: Place) -> [PassportSlot] {
        let locations = place.isNationalParkSystemSite ? store.stampLocations(in: place.id) : []
        guard locations.count >= 2 else {
            return [PassportSlot(place: place, location: nil, siblings: [])]
        }
        return locations.map {
            PassportSlot(place: place, location: $0, siblings: locations.map(\.id))
        }
    }

    /// A slot and its impressions, latest first, by `PassportSlotRule`.
    @ViewBuilder
    private func slotView(_ slot: PassportSlot, stamps slotStamps: [Stamp]) -> some View {
        let place = slot.place
        VStack(spacing: 8) {
            if let latest = slotStamps.first {
                Button {
                    viewing = slot
                } label: {
                    ZStack {
                        // A later visit adds a new impression that overlaps the old one, like
                        // a well-used paper page.
                        ForEach(slotStamps.dropFirst().prefix(2).reversed()) { older in
                            StampView(face: face(for: older, place: place), diameter: 120)
                                .opacity(0.35)
                        }
                        StampView(face: face(for: latest, place: place), diameter: 120)
                    }
                    .frame(width: 140, height: 140)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows every impression")
            } else {
                Button {
                    stamping = slot
                } label: {
                    StampSlotView(siteName: slot.location?.name ?? place.name, diameter: 120)
                        .frame(width: 140, height: 140)
                }
                .buttonStyle(.plain)
            }

            Text(place.name)
                .font(.custom("HelveticaNeue-Medium", size: 12, relativeTo: .caption))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let location = slot.location {
                Text(location.name)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if slotStamps.count > 1 {
                Text("\(slotStamps.count) impressions")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .contextMenu {
            Button("Stamp again") { stamping = slot }
            if !slotStamps.isEmpty {
                Button("Every impression") { viewing = slot }
            }
        }
    }

    private func face(for stamp: Stamp, place: Place) -> StampFace {
        StampFace(
            siteName: stampLocationName(stamp, place: place),
            date: stamp.date,
            stateCode: place.stampMark,
            region: region,
            country: place.country,
            seed: stamp.seed,
            isVerifiedOnSite: stamp.isVerifiedOnSite,

            calendar: UnigridsCalendar.gregorian(at: place),
            localName: place.leadLocalName?.text
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
