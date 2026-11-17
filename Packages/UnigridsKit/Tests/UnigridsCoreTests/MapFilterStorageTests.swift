import Foundation
import Testing
@testable import UnigridsCore

@Suite("Saved map filters")
struct MapFilterStorageTests {
    /// Exactly what 0.9.0's synthesized encoder wrote to `@AppStorage("map.filter")`.
    private let savedBy090 = """
    {"siteTypes":["nationalPark","battlefield"],"visits":"notVisited",\
    "states":["UT","AZ"],"activities":["hiking"],"stampLocationsOnly":true}
    """

    /// Kinds of site added since filters stored the kinds shown.
    private var newer: Set<SiteType> {
        Set(SiteType.allCases.filter {
            !MapFilter.siteTypesBeforeHiddenList.contains($0.rawValue)
        })
    }

    private func decode(_ json: String) throws -> MapFilter {
        try JSONDecoder().decode(MapFilter.self, from: Data(json.utf8))
    }

    @Test("a filter saved by 0.9.0 opens as it was")
    func legacyFilterDecodes() throws {
        let filter = try decode(savedBy090)
        // Kinds added since 0.9.0 are shown: the reader never chose to hide them.
        #expect(filter.siteTypes == Set<SiteType>([.nationalPark, .battlefield]).union(newer))
        #expect(filter.visits == .notVisited)
        #expect(filter.states == ["US-UT", "US-AZ"])
        #expect(filter.activities == [.hiking])
        #expect(filter.stampLocationsOnly)
    }

    @Test("a filter saved by 0.9.0 still narrows the same places")
    func legacyFilterNarrowsAlike() throws {
        let filter = try decode(savedBy090)
        let utah = Place(
            id: "np-zion", name: "Zion", designation: "National Park", kind: .nationalPark,
            states: [USState.named("UT")].compactMap(\.self),
            centre: Coordinate(latitude: 37.3, longitude: -113), activities: [.hiking]
        )
        #expect(filter.includes(utah, isVisited: false, hasStampLocation: true))
        #expect(!filter.includes(utah, isVisited: true, hasStampLocation: true))
    }

    @Test("a kind of place the filter never heard of is shown, not hidden")
    func newerKindsAreShown() throws {
        // Saved with every kind of 0.9.0 shown but battlefields: whatever kinds exist now,
        // only battlefields are hidden.
        let shown = MapFilter.siteTypesBeforeHiddenList.subtracting(["battlefield"])
        let json = #"{"siteTypes":\#(Array(shown).sorted().debugDescription)}"#
        let filter = try decode(json)
        #expect(filter.siteTypes == Set(SiteType.allCases).subtracting([.battlefield]))
    }

    @Test("a filter is stored as what it hides")
    func storedAsHidden() throws {
        let filter = MapFilter(siteTypes: Set(SiteType.allCases).subtracting([.memorial]))
        let data = try JSONEncoder().encode(filter)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hiddenSiteTypes"] as? [String] == ["memorial"])
        #expect(object["siteTypes"] == nil)
    }

    @Test("every filter survives a round trip")
    func roundTrip() throws {
        let filter = MapFilter(
            siteTypes: [.nationalPark, .wildlifeRefuge],
            visits: .visited,
            states: ["UT", "JP-01", "NO-34"],
            activities: [.camping, .hiking],
            stampLocationsOnly: true
        )
        let decoded = try JSONDecoder().decode(
            MapFilter.self, from: JSONEncoder().encode(filter)
        )
        #expect(decoded == filter)
        #expect(decoded.states == ["US-UT", "JP-01", "NO-34"])
    }

    @Test("what it cannot read it drops, keeping the rest")
    func unknownValuesDropped() throws {
        let filter = try decode("""
        {"siteTypes":["nationalPark","volcanoObservatory"],"visits":"sometimes",\
        "states":["UT","XX","NO-54"],"activities":["hiking","yodelling"]}
        """)
        #expect(filter.siteTypes == Set<SiteType>([.nationalPark]).union(newer))
        #expect(filter.visits == .all)
        #expect(filter.states == ["US-UT"])
        #expect(filter.activities == [.hiking])
        #expect(!filter.stampLocationsOnly)
    }

    @Test("an empty object is everything")
    func emptyIsEverything() throws {
        #expect(try decode("{}") == .everything)
    }
}
