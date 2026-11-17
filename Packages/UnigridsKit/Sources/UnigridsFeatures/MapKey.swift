import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// The map's key, filters and layers (SPECIFICATION.md §5). One sheet, because on a
// brochure map the legend and the choice of what to show are the same panel: every site
// type is listed with its pin, and each row's switch is the filter.

// MARK: - The button on the map

/// The key's entry point, bottom left of the map: a strip of colour swatches in the
/// brochure's legend box, with a count when something is filtered out.
struct MapKeyButton: View {
    @Environment(\.unigrid) private var style
    let filter: MapFilter
    let layers: Set<TransportLayer>
    let onTap: () -> Void

    /// One of each shape, in colours far apart, so the strip reads as "a key" at a glance
    /// without being a crowd of pins.
    private static let sample: [SiteType] = [
        .nationalPark, .nationalMonument, .statePark, .nationalForest, .wildlifeRefuge,
    ]

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(Self.sample) { type in
                        KeySwatch(type: type)
                            .opacity(filter.siteTypes.contains(type) ? 1 : 0.3)
                    }
                }
                Text("KEY")
                    .font(UnigridStyle.dataLabel)
                    .tracking(1.2)
                    .foregroundStyle(style.ink)
                if filter.narrowedCount > 0 {
                    Text("\(filter.narrowedCount)")
                        .font(.custom("HelveticaNeue-Bold", size: 11, relativeTo: .caption2))
                        .monospacedDigit()
                        .foregroundStyle(style.onAccent)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(style.accent)
                }
                if !layers.isEmpty {
                    Image(.roads)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(style.inkSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(style.panel)
            .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map key and filters")
        .accessibilityValue(
            filter.isNarrowed ? "\(filter.narrowedCount) filters on" : "Showing everything"
        )
    }
}

/// A pin without its pictogram: the type's shape and colour, keylined in white.
struct KeySwatch: View {
    let type: SiteType
    var side: CGFloat = 13

    var body: some View {
        let shape = MarkerShape(tier: type.tier)
        ZStack {
            MarkerOutline(shape).fill(Color(SiteInk.pictogram))
            MarkerOutline(shape).fill(Color(type.ink.pin)).padding(1.25)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - The layers menu

/// Base map and transport layers, one tap from the toolbar.
struct MapLayersMenu: View {
    @Environment(\.referenceStore) private var abroadStore

    /// Whether railways abroad ship, so the rail layer is more than Amtrak's.
    private var hasAbroad: Bool {
        abroadStore.nationalParks.contains { $0.country != .unitedStates }
    }

    @Binding var layers: Set<TransportLayer>
    @Binding var basemap: AtlasBasemap

    var body: some View {
        Menu {
            Picker("Base map", selection: $basemap) {
                ForEach(AtlasBasemap.allCases) { option in
                    Label(option.name, systemImage: option.symbol).tag(option)
                }
            }
            Section("Overlay") {
                ForEach(TransportLayer.allCases) { layer in
                    Toggle(isOn: binding(for: layer)) {
                        Label(
                            layer.name(withRailAbroad: hasAbroad),
                            systemImage: UnigridsSymbol.transport(layer)
                        )
                    }
                }
            }
        } label: {
            Label("Layers", symbol: .layers)
        }
    }

    private func binding(for layer: TransportLayer) -> Binding<Bool> {
        Binding(
            get: { layers.contains(layer) },
            set: { isOn in
                if isOn {
                    layers.insert(layer)
                } else {
                    layers.remove(layer)
                }
            }
        )
    }
}

// MARK: - The sheet

struct MapKeySheet: View {
    @Environment(\.referenceStore) private var abroadStore

    /// Whether railways abroad ship, so the rail layer is more than Amtrak's.
    private var hasAbroad: Bool {
        abroadStore.nationalParks.contains { $0.country != .unitedStates }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    @Binding var filter: MapFilter
    @Binding var layers: Set<TransportLayer>
    @Binding var basemap: AtlasBasemap
    let counts: [SiteType: Int]

    var body: some View {
        SheetPage(
            "Map key",
            kicker: filter.isNarrowed ? "Filtered" : "Every place shown",
            actions: .done { dismiss() },
            width: 520,
            height: 720
        ) {
            List {
                ForEach(SiteType.Group.allCases) { group in
                    Section {
                        // A kind with no places behind it — another country's, before its
                        // data ships — has no row.
                        ForEach(group.types.filter { counts[$0, default: 0] > 0 }) { type in
                            SiteTypeToggle(
                                type: type,
                                count: counts[type] ?? 0,
                                isOn: typeBinding(type)
                            )
                        }
                    } header: {
                        GroupHeader(group: group, filter: $filter)
                    }
                }

                Section {
                    Picker("Visits", selection: $filter.visits) {
                        ForEach(MapFilter.Visits.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Kicker("Your log")
                }

                Section {
                    Toggle(isOn: $filter.stampLocationsOnly) {
                        Label {
                            Text("Has a passport stamp")
                        } icon: {
                            StampIcon()
                        }
                    }
                    NavigationLink {
                        ActivityFilterList(selection: $filter.activities)
                    } label: {
                        FilterSummaryRow(
                            title: "Activities",
                            symbol: "figure.hiking",
                            summary: activitySummary
                        )
                    }
                    NavigationLink {
                        SubdivisionFilterList(countries: countries, selection: $filter.states)
                    } label: {
                        FilterSummaryRow(
                            title: countries.count > 1 ? "Regions" : "States and territories",
                            symbol: "map",
                            summary: stateSummary
                        )
                    }
                } header: {
                    Kicker("Narrow")
                } footer: {
                    FormNote(
                        "Activities come from the National Park Service's own listings, so "
                            + "narrowing by one shows NPS sites only."
                    )
                }

                Section {
                    ForEach(TransportLayer.allCases) { layer in
                        TransportLayerToggle(layer: layer, isOn: layerBinding(layer))
                    }
                    Picker("Base map", selection: $basemap) {
                        ForEach(AtlasBasemap.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Kicker("Layers")
                } footer: {
                    FormNote(
                        "Roads and railways from the US DOT National Transportation Atlas "
                            + "Database. US highways appear from regional zoom, Amtrak stations "
                            + "close up."
                            + (hasAbroad ? " Railways in Japan and Norway from OpenStreetMap "
                                + "contributors, ODbL." : "")
                    )
                }

                Section {
                    LegendKey()
                } header: {
                    Kicker("Reading the map")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear filters") { filter = .everything }
                        .disabled(!filter.isNarrowed)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var activitySummary: String {
        filter.activities.isEmpty ? "Any"
            : PlaceActivity.allCases.filter(filter.activities.contains).map(\.name)
            .joined(separator: ", ")
    }

    /// The countries with places in the data, the US first.
    private var countries: [Country] {
        let present = Set(abroadStore.nationalParks.map(\.country))
        return Country.allCases.filter(present.contains)
    }

    /// "AZ, UT" for states, as it always read; a prefecture or county by name.
    private var stateSummary: String {
        filter.states.isEmpty ? "Everywhere"
            : filter.states.compactMap(Subdivision.named)
            .map { $0.usState?.code ?? $0.name }
            .sorted()
            .joined(separator: ", ")
    }

    private func typeBinding(_ type: SiteType) -> Binding<Bool> {
        Binding(
            get: { filter.siteTypes.contains(type) },
            set: { isOn in
                if isOn {
                    filter.siteTypes.insert(type)
                } else {
                    filter.siteTypes.remove(type)
                }
            }
        )
    }

    private func layerBinding(_ layer: TransportLayer) -> Binding<Bool> {
        Binding(
            get: { layers.contains(layer) },
            set: { isOn in
                if isOn {
                    layers.insert(layer)
                } else {
                    layers.remove(layer)
                }
            }
        )
    }
}

/// A group's head in the key, with a switch for the whole group.
private struct GroupHeader: View {
    let group: SiteType.Group
    @Binding var filter: MapFilter

    private var allOn: Bool {
        group.types.allSatisfy(filter.siteTypes.contains)
    }

    var body: some View {
        HStack {
            Kicker(group.name)
            Spacer()
            Button(allOn ? "Hide all" : "Show all") {
                if allOn {
                    filter.siteTypes.subtract(group.types)
                } else {
                    filter.siteTypes.formUnion(group.types)
                }
            }
            .font(UnigridStyle.caption)
            .buttonStyle(.borderless)
        }
    }
}

/// One site type in the key: its pin, its name, how many there are, and the switch.
private struct SiteTypeToggle: View {
    @Environment(\.unigrid) private var style
    let type: SiteType
    let count: Int
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SitePin(type: type)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.name)
                        .font(UnigridStyle.rowTitle)
                    Text("\(count.formatted()) · \(type.detail)")
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityLabel("\(type.name), \(count)")
    }
}

/// A transport layer in the key, with a sample of how it is drawn.
private struct TransportLayerToggle: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let layer: TransportLayer

    private var abroad: Bool {
        store.nationalParks.contains { $0.country != .unitedStates }
    }

    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                TransportSample(layer: layer)
                    .frame(width: 30, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name(withRailAbroad: abroad))
                        .font(UnigridStyle.rowTitle)
                    Text(layer.detail(withRailAbroad: abroad))
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
            }
        }
    }
}

private struct FilterSummaryRow: View {
    @Environment(\.unigrid) private var style
    let title: String
    let symbol: String
    let summary: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(summary)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
                .lineLimit(1)
        }
    }
}

/// Pick activities a place must offer.
private struct ActivityFilterList: View {
    @Binding var selection: Set<PlaceActivity>

    var body: some View {
        List {
            Section {
                ForEach(PlaceActivity.allCases) { activity in
                    Button {
                        if selection.contains(activity) {
                            selection.remove(activity)
                        } else {
                            selection.insert(activity)
                        }
                    } label: {
                        HStack {
                            Text(activity.name)
                            Spacer()
                            if selection.contains(activity) {
                                Image(.seen)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(activity) ? .isSelected : [])
                }
            } footer: {
                FormNote("Places that list every activity you pick.")
            }
        }
        .paperPage()
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem {
                Button("Clear") { selection = [] }
                    .disabled(selection.isEmpty)
            }
        }
    }
}
