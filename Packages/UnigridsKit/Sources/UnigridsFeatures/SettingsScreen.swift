import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Settings, About and the Attributions screen the open-data licences require
/// (SPECIFICATION.md §15).
public struct SettingsScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style

    /// The app's only persisted preferences. Appearance is a property of this device, not
    /// of the reader's log, so it stays in `UserDefaults` and does not sync through
    /// CloudKit with their visits.
    @AppStorage(AppearanceDefaults.appearance)
    private var appearance = AppearancePreference.standard
    @AppStorage(AppearanceDefaults.palette)
    private var palette = Palette.standard
    @AppStorage(OnboardingDefaults.seen) private var onboardingSeen = true

    public init() {}

    /// "0.9.0", from the app's own bundle.
    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public var body: some View {
        List {
            Section {
                BandHeader("Settings", kicker: appVersion.map { "Unigrids \($0)" })
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Palette", selection: $palette) {
                    ForEach(Palette.allCases) { option in
                        Label {
                            Text(option.name)
                        } icon: {
                            PaletteSwatch(palette: option)
                        }
                        .tag(option)
                    }
                }

                Text(palette.detail)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            } header: {
                SectionHead("Appearance")
            }

            Section {
                AppIconPicker()
            } header: {
                SectionHead("App icon")
            } footer: {
                Text(
                    "A stack of Unigrid brochures over the park you pick, with that "
                        + "park's own brochure on top."
                )
                .font(UnigridStyle.caption)
            }

            Section {
                VisitDetectionToggle()
            } header: {
                SectionHead("Arrivals")
            } footer: {
                Text(
                    "With location set to Always, Unigrids watches the outlines of the parks "
                        + "nearest you and asks whether to log a visit when you arrive. It "
                        + "happens on this device; your location is never stored or sent."
                )
                .font(UnigridStyle.caption)
            }

            YourDataSection()

            BrochureStorageSection()

            Section {
                LabeledContent("Places on the map", value: store.places.count.formatted())
                LabeledContent(
                    "Drawn with their outline",
                    value: store.boundaries.count.formatted()
                )
                LabeledContent("Trails measured", value: store.allTrails.count.formatted())
                if !store.manifest.builtOn.isEmpty {
                    LabeledContent(
                        "Gathered",
                        value: "\(store.manifest.builtOn), version \(store.manifest.version)"
                    )
                }
                LabeledContent(
                    "Live park alerts",
                    value: NPSAlerts.isConfigured ? "On" : "Not in this build"
                )
                if let note = store.manifest.note {
                    Text(note)
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
                NavigationLink("Photo credits") {
                    PhotoCreditsScreen()
                }
            } header: {
                SectionHead("Reference data")
            } footer: {
                Text(
                    "Everything about the places — names, outlines, guides, trails, photos — "
                        + "comes inside the app from public sources and is refreshed with each "
                        + "release. Only alerts, forecasts and weather are fetched live."
                )
                .font(UnigridStyle.caption)
            }

            Section {
                ForEach(Attribution.all) { attribution in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attribution.name)
                            .font(UnigridStyle.rowTitle)
                        Text(attribution.terms)
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                SectionHead("Attributions")
            }

            Section {
                NonAffiliationNotice()
                Text(
                    "Trail and map information here is for planning, not wilderness "
                        + "navigation. Check current conditions and ranger advice before "
                        + "you go."
                )
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Show the welcome again") { onboardingSeen = false }
            } header: {
                SectionHead("About")
            }
        }
        .paperPage()
        .navigationTitle("Settings")
    }
}

#if os(iOS)
    /// Settings from the root of every tab on iPhone and iPad. The Mac has its own
    /// Settings window, on ⌘, and in the app menu.
    struct SettingsToolbarItem: ToolbarContent {
        var body: some ToolbarContent {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Label("Settings", symbol: .settings)
                }
            }
        }
    }
#endif

/// Every photograph the app reuses, with its credit and licence, in one place
/// (SPECIFICATION.md §15).
struct PhotoCreditsScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style

    private var entries: [(place: Place, images: [GuideImage])] {
        store.places
            .sorted { ($0.tier, $0.name) < ($1.tier, $1.name) }
            .compactMap { place in
                let guide = store.guide(for: place.id)
                var images = [guide?.hero ?? place.image].compactMap(\.self)
                images += guide?.gallery ?? []
                return images.isEmpty ? nil : (place, images)
            }
    }

    var body: some View {
        List {
            Section {
                Text(
                    "National Park Service photographs are public domain and are used as the "
                        + "NPS credits them. Photographs of other places come from Wikimedia "
                        + "Commons under the licence shown, each linked to its source."
                )
                .font(UnigridStyle.proseSmall)
                .foregroundStyle(style.inkSecondary)
            }
            ForEach(entries, id: \.place.id) { entry in
                Section {
                    ForEach(entry.images) { image in
                        PhotoCredit(image: image)
                    }
                } header: {
                    Text(entry.place.name)
                        .font(UnigridStyle.rowTitle)
                }
            }
        }
        .paperPage()
        .navigationTitle("Photo credits")
    }
}

/// The attributions the bundled and fetched data require, in one list so the screen and
/// the repository's own README cannot drift apart.
struct Attribution: Identifiable {
    let name: String
    let terms: String

    var id: String {
        name
    }

    static let all: [Attribution] = [
        Attribution(
            name: "National Park Service",
            terms: "Park descriptions, fees, hours, visitor centres, alerts and photographs from "
                + "the NPS Data API; outlines from the NPS Land Resources Division. Public-domain "
                + "US government works, used without the NPS arrowhead and without implying "
                + "endorsement."
        ),
        Attribution(
            name: "USGS PAD-US",
            terms: "Every state park, and monument and refuge outlines and areas, from the "
                + "Protected Areas Database of the United States, a public-domain USGS data "
                + "release; state park managers as PAD-US names them."
        ),
        Attribution(
            name: "NPS Visitor Use Statistics",
            terms: "Monthly and annual recreation visits to National Park Service sites, from "
                + "the NPS's published visitor use data, dedicated to the public domain (CC0)."
        ),
        Attribution(
            name: "Wikipedia",
            terms: "Overviews of places with no agency prose, adapted from the opening of each "
                + "place's Wikipedia article — used only where the article's title and location "
                + "match the place — under CC BY-SA 4.0, credited and linked on each page."
        ),
        Attribution(
            name: "Other federal lands",
            terms: "National forest and grassland boundaries from the US Forest Service; "
                + "wildlife refuge boundaries from the US Fish and Wildlife Service; National "
                + "Conservation Lands from the Bureau of Land Management; National Natural "
                + "Landmarks from the National Park Service; scenic byways from the Federal "
                + "Highway Administration; state outlines from the US Census Bureau. All "
                + "public-domain US government works."
        ),
        Attribution(
            name: "National Transportation Atlas Database",
            terms: "Interstates, US highways and the Amtrak network and stations, from the US "
                + "Department of Transportation's Bureau of Transportation Statistics. A US "
                + "government work, unrestricted public use."
        ),
        Attribution(
            name: "Trails and elevation",
            terms: "Trail lines from the NPS Public Trails dataset, and for Sequoia and Kings "
                + "Canyon from OpenStreetMap; elevation, and the highest and lowest ground of "
                + "parks the NPS gives no figure for, from the USGS 3D Elevation Program "
                + "(3DEP), public domain. Measured by Unigrids."
        ),
        Attribution(
            name: "Official brochures",
            terms: "Brochures and maps are National Park Service publications, fetched from "
                + "nps.gov and shown as published, with their credits."
        ),
        Attribution(
            name: "Wikimedia Commons",
            terms: "Photographs of state parks, monuments and refuges, each credited to its "
                + "photographer under the licence shown with it."
        ),
        Attribution(
            name: "OpenStreetMap",
            terms: "Trail lines in Sequoia and Kings Canyon, and the roads and water drawn in "
                + "the offline park maps: © OpenStreetMap contributors, available under the "
                + "Open Database Licence (ODbL)."
        ),
        Attribution(
            name: "Apple Maps",
            terms: "Base maps, satellite imagery and 3D terrain."
        ),
        Attribution(
            name: "Open-Meteo",
            terms: "Historical weather from the ERA5 reanalysis, under CC BY 4.0."
        ),
    ]
}

/// The brochures kept on this device, their size, and the way to clear them
/// (SPECIFICATION.md §6).
struct BrochureStorageSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(BrochureLibrary.self) private var library: BrochureLibrary?

    var body: some View {
        if let library {
            Section {
                if library.entries.isEmpty {
                    Text("None yet. A brochure is kept here once you open it.")
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
                ForEach(library.entries.sorted { $0.savedAt > $1.savedAt }) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.place(UnigridsID(entry.placeID))?.name ?? entry.placeID)
                                .font(UnigridStyle.rowTitle)
                            Text(entry.title)
                                .font(UnigridStyle.rowDetail)
                                .foregroundStyle(style.inkSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(entry.bytes),
                            countStyle: .file
                        ))
                        .font(UnigridStyle.dataLabel)
                        .monospacedDigit()
                        .foregroundStyle(style.inkSecondary)
                        Button(role: .destructive) {
                            library.remove(entry)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                if !library.entries.isEmpty {
                    Button("Clear every brochure", role: .destructive) {
                        library.removeAll()
                    }
                }
            } header: {
                SectionHead(
                    "Brochures on this device",
                    detail: ByteCountFormatter.string(
                        fromByteCount: Int64(library.totalBytes), countStyle: .file
                    )
                )
            } footer: {
                Text(
                    "Fetched from nps.gov when first opened. Parks on an upcoming trip are kept "
                        + "for offline automatically, on Wi-Fi."
                )
                .font(UnigridStyle.caption)
            }
        }
    }
}

/// The key the onboarding's seen-it flag is stored under.
public enum OnboardingDefaults {
    public static let seen = "onboarding.seen"
}
