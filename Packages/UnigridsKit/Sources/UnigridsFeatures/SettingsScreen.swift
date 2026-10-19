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

    @Query private var visits: [Visit]
    @Query private var stamps: [Stamp]
    @Query private var trips: [Trip]

    public init() {}

    public var body: some View {
        List {
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
                LabeledContent("Visits", value: "\(visits.count)")
                LabeledContent("Stamps", value: "\(stamps.count)")
                LabeledContent("Trips", value: "\(trips.count)")
                if let files = exportFiles {
                    ShareLink(item: files.json) {
                        Label("Export everything (JSON)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: files.csv) {
                        Label("Export visits (CSV)", systemImage: "tablecells")
                    }
                }
                Text(
                    "Your log lives on this device and in your own iCloud. "
                        + "There are no accounts and no servers, so the developer never "
                        + "holds any of it."
                )
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
            } header: {
                SectionHead("Your data")
            }

            Section {
                LabeledContent("Dataset version", value: "\(store.manifest.version)")
                LabeledContent("Provenance", value: store.manifest.provenance.name)
                if !store.manifest.builtOn.isEmpty {
                    LabeledContent("Built", value: store.manifest.builtOn)
                }
                LabeledContent("Places", value: "\(store.places.count)")
                LabeledContent(
                    "Live alerts",
                    value: NPSAlerts.isConfigured ? "On" : "Off in this build"
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
                Text("Reference data ships inside the app and is replaced with each release.")
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

    /// The export files, written fresh to the temporary directory whenever the screen is
    /// drawn. They are a hand-off to the share sheet, not a copy kept anywhere.
    private var exportFiles: (json: URL, csv: URL)? {
        guard let document = try? LogExport.document(
            context: context,
            name: { store.place($0)?.name }
        ),
            let json = try? LogExport.json(document)
        else { return nil }
        let folder = FileManager.default.temporaryDirectory
        let jsonURL = folder.appendingPathComponent("Unigrids log.json")
        let csvURL = folder.appendingPathComponent("Unigrids visits.csv")
        do {
            try json.write(to: jsonURL, options: .atomic)
            try LogExport.visitsCSV(document).write(to: csvURL, atomically: true, encoding: .utf8)
            return (jsonURL, csvURL)
        } catch {
            return nil
        }
    }
}

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
            terms: "State park, monument and refuge outlines and areas from the Protected Areas "
                + "Database of the United States, a public-domain USGS data release."
        ),
        Attribution(
            name: "Wikimedia Commons",
            terms: "Photographs of state parks, monuments and refuges, each credited to its "
                + "photographer under the licence shown with it."
        ),
        Attribution(
            name: "OpenStreetMap",
            terms: "© OpenStreetMap contributors, available under the Open Database "
                + "Licence (ODbL)."
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

/// The key the onboarding's seen-it flag is stored under.
public enum OnboardingDefaults {
    public static let seen = "onboarding.seen"
}
