import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// "By train": the nearest Amtrak station and the services that call there, from the
/// bundled rail network. Shown only where there is a station within a hundred kilometres;
/// most parks have none, and an empty panel would say nothing.
struct ByTrainPanel: View {
    @Environment(\.unigrid) private var style
    let place: Place
    let access: TrainAccess?

    var body: some View {
        if let access {
            UnigridPanel(title: "By train") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "tram.fill")
                            .foregroundStyle(style.inkSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(access.station.name)
                                .font(UnigridStyle.itemTitle)
                                .foregroundStyle(style.ink)
                            Text(stationLine(access))
                                .font(UnigridStyle.caption)
                                .foregroundStyle(style.inkSecondary)
                        }
                    }
                    Text(distanceLine(access))
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !access.services.isEmpty {
                        UnigridDataRow(
                            label: "Served by",
                            value: ListFormatter.localizedString(byJoining: access.services)
                        )
                    }
                    Text("Straight-line distance. Check Amtrak for schedules and onward travel.")
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
            }
        }
    }

    /// The nearest station to a place, worked out off the main actor once the rail
    /// network is loaded. Called by the page that shows the panel, which is never empty
    /// and so always runs its tasks.
    @MainActor
    static func access(
        to place: Place,
        store: any ReferenceStore,
        transport: TransportStore?
    ) async -> TrainAccess? {
        guard let transport else { return nil }
        await transport.load(from: store)
        let network = transport.network
        let boundary = store.boundary(for: place.id)
        return await Task.detached(priority: .utility) {
            network.trainAccess(to: place, boundary: boundary)
        }.value
    }

    private func stationLine(_ access: TrainAccess) -> String {
        [
            "Amtrak \(access.station.code)",
            access.station.city,
            access.station.state?.name,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    private func distanceLine(_ access: TrainAccess) -> String {
        if access.measuredToBoundary, access.metres == 0 {
            return "The station is within \(place.name)'s boundary."
        }
        if access.measuredToBoundary, access.metres < 1000 {
            return "The station is at the edge of \(place.name), "
                + "under a kilometre from its boundary."
        }
        let distance = UnigridsFormat.distance(metres: access.metres)
        let to = access.measuredToBoundary ? "the boundary" : "\(place.name)"
        return "\(distance) from \(to)."
    }
}
