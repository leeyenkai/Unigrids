import Foundation
import UnigridsCore
import UnigridsReference

extension AlertsCenter {
    /// Every country's warnings, for the map's badges: the NPS's, then one fetch for all
    /// of Japan's volcanoes, Varsom a few Norwegian parks at a time, and one fetch for all
    /// of New Zealand's volcanoes.
    func refreshEveryCountry(store: any ReferenceStore) async {
        await refreshIfStale()
        let parks = Dictionary(grouping: store.nationalParks, by: \.country)
        let japan = parks[.japan] ?? []
        await refreshJapan(japan.map { ($0, store.boundary(for: $0.id)) })
        await refreshNorway(parks[.norway] ?? [])
        let newZealand = parks[.newZealand] ?? []
        await refreshNewZealand(newZealand.map { ($0, store.boundary(for: $0.id)) })
    }
}
