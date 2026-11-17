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
                            PassportBookReader(
                                regions: PassportRegion.regions(in: book), region: region
                            )
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
                    PassportBookReader(
                        regions: PassportRegion.regions(in: region.country), region: region
                    )
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
