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

    @Query private var visits: [Visit]
    @Query private var stamps: [Stamp]

    public init() {}

    public var body: some View {
        List {
            Section("Your data") {
                LabeledContent("Visits", value: "\(visits.count)")
                LabeledContent("Stamps", value: "\(stamps.count)")
                Text(
                    "Your log lives on this device and in your own iCloud. "
                        + "There are no accounts and no servers, so the developer never "
                        + "holds any of it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Dataset version", value: "\(store.manifest.version)")
                LabeledContent("Provenance", value: store.manifest.provenance.name)
                if !store.manifest.builtOn.isEmpty {
                    LabeledContent("Built", value: store.manifest.builtOn)
                }
                LabeledContent("Places", value: "\(store.places.count)")
                if let note = store.manifest.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reference data")
            } footer: {
                Text("Reference data ships inside the app and is replaced with each release.")
            }

            Section("Attributions") {
                ForEach(Attribution.all) { attribution in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attribution.name)
                            .font(.subheadline.weight(.medium))
                        Text(attribution.terms)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("About") {
                NonAffiliationNotice()
                Text(
                    "Trail and map information here is for planning, not wilderness "
                        + "navigation. Check current conditions and ranger advice before "
                        + "you go."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Settings")
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
            terms: "Park text, maps and brochures are public-domain US government works. "
                + "Used without the NPS arrowhead and without implying endorsement. Some "
                + "photographs and artwork in NPS publications carry third-party rights."
        ),
        Attribution(
            name: "OpenStreetMap",
            terms: "© OpenStreetMap contributors, available under the Open Database "
                + "Licence (ODbL)."
        ),
        Attribution(
            name: "Open-Meteo",
            terms: "Historical weather from the ERA5 reanalysis, under CC BY 4.0."
        ),
        Attribution(
            name: "Recreation Information Database",
            terms: "Facility and campground data under CC BY."
        ),
        Attribution(
            name: "USGS",
            terms: "PAD-US protected-area boundaries and 3DEP elevation, public domain."
        ),
        Attribution(
            name: "Apple Weather",
            terms: "Weather data provided by Apple Weather."
        ),
    ]
}
