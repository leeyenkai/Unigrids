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

    // A Mac pop-up button shows the swatch in its own height; iOS shows it in the menu.
    #if os(macOS)
        private static let swatchSize: CGFloat = 16
    #else
        private static let swatchSize: CGFloat = 26
    #endif

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
                            PaletteSwatch(palette: option, size: Self.swatchSize)
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
                #if os(iOS)
                    FormNote(
                        "A stack of Unigrid brochures over the park you pick, with that "
                            + "park's own brochure on top."
                    )
                #endif
            }

            Section {
                VisitDetectionToggle()
            } header: {
                SectionHead("Arrivals")
            } footer: {
                #if os(iOS)
                    FormNote(
                        "With location set to Always, Unigrids watches the outlines of the parks "
                            + "nearest you and asks whether to log a visit when you arrive. It "
                            + "happens on this device; your location is never stored or sent."
                    )
                #endif
            }

            YourDataSection()

            BrochureStorageSection()

            OfflineMapsSection()

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
                    store.nationalParks.contains { $0.country != .unitedStates }
                        ? "Live park alerts, US" : "Live park alerts",
                    value: NPSAlerts.isConfigured ? "On" : "Off, no NPS key"
                )
                if store.nationalParks.contains(where: { $0.country != .unitedStates }) {
                    // JMA's, Varsom's and GeoNet's warnings need no key, so they are on in
                    // every build.
                    LabeledContent("Live warnings abroad", value: "On")
                }
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
                FormNote(
                    "Everything about the places — names, outlines, guides, trails, photos — "
                        + "comes inside the app from public sources and is refreshed with each "
                        + "release. Only alerts, forecasts and weather are fetched live."
                )
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
                .help("Settings")
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
                BandHeader("Photo credits", kicker: "\(entries.count) places")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
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

/// The offline park maps this build carries, with their sizes.
struct OfflineMapsSection: View {
    @Environment(\.unigrid) private var style
    private let packs = OfflinePackCatalogue.bundled.packs

    var body: some View {
        Section {
            if packs.isEmpty {
                Text("This build carries no offline maps.")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            ForEach(packs) { pack in
                LabeledContent(
                    pack.name,
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(pack.bytes),
                        countStyle: .file
                    )
                )
            }
        } header: {
            SectionHead("Offline park maps", detail: packs.isEmpty ? nil : "\(packs.count)")
        } footer: {
            FormNote(
                "Topographic maps with every trail, inside the app, for when there is no signal. "
                    + "Open one from the park's guide or a trail's page."
            )
        }
    }
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
                            Label("Delete", symbol: .delete)
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
                FormNote(
                    "Fetched from nps.gov when first opened. Parks on an upcoming trip are kept "
                        + "for offline automatically, on Wi-Fi."
                )
            }
        }
    }
}

/// The key the onboarding's seen-it flag is stored under.
public enum OnboardingDefaults {
    public static let seen = "onboarding.seen"
}
