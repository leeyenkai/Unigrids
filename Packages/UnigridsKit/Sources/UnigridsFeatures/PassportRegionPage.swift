import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

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
    /// Wide enough for a two-page spread: the title page on the left, the slots on the
    /// right, as the open book lies on a desk (§9).
    @State private var isSpread = false

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
        let slotPages = VStack(alignment: .leading, spacing: 28) {
            slotSection("National parks", places: parks, byPlace: byPlace)
            slotSection("Other NPS sites", places: units, byPlace: byPlace)
            if !beyond.isEmpty {
                slotSection(
                    region.country.passportBeyondTitle, places: beyond, byPlace: byPlace
                )
            }
        }
        Group {
            if isSpread {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            titlePage(npsSites: parks + units, byPlace: byPlace)
                            RegionTitleSummary(
                                region: region,
                                sites: parks + units,
                                stamped: Set(byPlace.keys),
                                beyond: beyond.count
                            )
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(width: 320)
                    BookGutter()
                    ScrollView {
                        slotPages.padding(.vertical, 20)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        titlePage(npsSites: parks + units, byPlace: byPlace)
                        slotPages
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { isSpread = $0 }
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
                localName: place.leadLocalName?.text,
                emblem: store.emblem(for: place)
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
                    .typeset(for: location.name)
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
            localName: place.leadLocalName?.text,
            emblem: store.emblem(for: place)
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
