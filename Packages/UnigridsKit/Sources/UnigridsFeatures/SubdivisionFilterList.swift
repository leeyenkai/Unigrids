import SwiftUI
import UnigridsCore
import UnigridsDesign

/// Pick states, prefectures or counties to narrow the map to (SPECIFICATION.md §5).
///
/// One country: its states and territories, as the list always read. Several: a section
/// per country. The filter holds subdivision codes — `US-UT`, `JP-01`, `NO-34` — so a
/// choice made before other countries shipped still means what it did.
struct SubdivisionFilterList: View {
    @Environment(\.unigrid) private var style
    let countries: [Country]
    @Binding var selection: Set<String>
    @State private var query = ""

    /// The short form beside each name, as the Stats tile maps print it: `UT`, `北海道`,
    /// `TRO`.
    private static let labels: [String: String] = Dictionary(
        Country.allCases.flatMap { SubdivisionTileGrid.grid(for: $0).tiles }
            .map { ($0.code, $0.label) },
        uniquingKeysWith: { first, _ in first }
    )

    private func subdivisions(in country: Country) -> [Subdivision] {
        let all = Subdivision.all(in: country).sorted { $0.name < $1.name }
        guard !query.isEmpty else { return all }
        return all.filter {
            SearchText.contains($0.name, query)
                || SearchText.contains(Self.labels[$0.code] ?? "", query)
                || $0.usState?.code.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    private var isWorld: Bool {
        countries.count > 1
    }

    var body: some View {
        List {
            ForEach(countries, id: \.self) { country in
                let rows = subdivisions(in: country)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { row($0, in: country) }
                    } header: {
                        if isWorld {
                            Text(country.name)
                        }
                    }
                }
            }
        }
        .paperPage()
        .searchable(
            text: $query,
            prompt: isWorld ? "State, prefecture or county" : "State or territory"
        )
        .navigationTitle(isWorld ? "Regions" : "States")
        .toolbar {
            ToolbarItem {
                Button("Clear") { selection = [] }
                    .disabled(selection.isEmpty)
            }
        }
    }

    private func row(_ subdivision: Subdivision, in country: Country) -> some View {
        let chosen = selection.contains(subdivision.code)
        return Button {
            if chosen {
                selection.remove(subdivision.code)
            } else {
                selection.insert(subdivision.code)
            }
        } label: {
            HStack {
                Text(subdivision.name)
                Spacer()
                if let label = Self.labels[subdivision.code] {
                    Text(label)
                        .font(UnigridStyle.dataLabel)
                        .foregroundStyle(style.inkSecondary)
                        .typeset(in: country == .japan ? "ja" : "en")
                }
                if chosen {
                    Image(.seen)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
