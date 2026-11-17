import Foundation
import Testing
@testable import UnigridsCore

@Suite("Countries and subdivisions")
struct CountryTests {
    @Test("an identifier says its country; anything un-namespaced is American")
    func countryFromIdentifier() {
        #expect(Country.inferred(from: "np-zion") == .unitedStates)
        #expect(Country.inferred(from: "nps-arpo") == .unitedStates)
        #expect(Country.inferred(from: "poi-zion-angels-landing") == .unitedStates)
        #expect(Country.inferred(from: "jp-np-shiretoko") == .japan)
        #expect(Country.inferred(from: "no-np-jotunheimen") == .norway)
        #expect(Country.inferred(from: "poi-jp-shiretoko-oshinkoshin-falls") == .japan)
        #expect(Country.inferred(from: "trail-no-jotunheimen-besseggen") == .norway)
        // A US park whose slug merely starts with the letters stays American.
        #expect(Country.inferred(from: "poi-north-cascades-diablo-lake") == .unitedStates)
        #expect(Country.inferred(from: "") == .unitedStates)
    }

    @Test("Japan's 47 prefectures in ISO order")
    func prefectures() {
        let all = Subdivision.all(in: .japan)
        #expect(all.count == 47)
        #expect(all.first == Subdivision(code: "JP-01", name: "Hokkaido"))
        #expect(Subdivision.named("JP-13")?.name == "Tokyo")
        #expect(all.last == Subdivision(code: "JP-47", name: "Okinawa"))
    }

    @Test("Norway's fifteen counties of 2024, and Svalbard")
    func norwegianCounties() {
        let all = Subdivision.all(in: .norway)
        #expect(all.count == 16)
        #expect(Subdivision.named("NO-55")?.name == "Troms")
        #expect(Subdivision.named("NO-21")?.name == "Svalbard")
        // The counties dissolved in 2024 are not codes any more.
        #expect(Subdivision.named("NO-54") == nil)
        #expect(Subdivision.named("NO-30") == nil)
    }

    @Test("codes are unique across every country")
    func codesAreUnique() {
        let codes = Country.allCases.flatMap { Subdivision.all(in: $0) }.map(\.code)
        #expect(Set(codes).count == codes.count)
        for country in Country.allCases {
            #expect(Subdivision.all(in: country).allSatisfy { $0.country == country })
        }
    }

    @Test("a bare two-letter code is a US state, as saved filters hold them")
    func bareCodesAreStates() {
        #expect(Subdivision.named("UT") == Subdivision(code: "US-UT", name: "Utah"))
        #expect(Subdivision.named("ut")?.usState?.code == "UT")
        #expect(Subdivision.named("JP-01")?.usState == nil)
    }

    @Test("an unknown subdivision does not decode")
    func unknownCodeThrows() {
        let data = Data(#""JP-99""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Subdivision.self, from: data)
        }
    }
}

@Suite("Places abroad")
struct PlaceCountryTests {
    private func decode(_ json: String) throws -> Place {
        try JSONDecoder().decode(Place.self, from: Data(json.utf8))
    }

    @Test("a record with no country is American, its subdivisions its states")
    func defaultsToTheUS() throws {
        let place = try decode("""
        {"id": "np-zion", "name": "Zion", "kind": "nationalPark", "states": ["UT"],
         "centre": {"latitude": 37.3, "longitude": -113.0}}
        """)
        #expect(place.country == .unitedStates)
        #expect(place.subdivisions.map(\.code) == ["US-UT"])
        #expect(place.regionLine == "Utah")
        #expect(place.localNames.isEmpty)
    }

    @Test("a US place's region line is its states line, however many states")
    func usRegionLineUnchanged() {
        let codes = ["MN", "WI", "IA", "IL", "MO", "KY", "TN", "AR", "MS", "LA"]
        let place = Place(
            id: "byway-great-river-road", name: "Great River Road", designation: "",
            kind: .scenicByway, states: codes.compactMap(USState.named),
            centre: Coordinate(latitude: 38, longitude: -90)
        )
        #expect(place.regionLine == place.statesDescription)
    }

    @Test("a place abroad carries its own subdivisions and local names")
    func placeAbroad() throws {
        let place = try decode("""
        {"id": "jp-np-shiretoko", "name": "Shiretoko", "kind": "nationalPark",
         "country": "JP", "subdivisions": ["JP-01"], "timeZoneID": "Asia/Tokyo",
         "localNames": [{"language": "ja", "text": "知床国立公園"}],
         "centre": {"latitude": 44.1, "longitude": 145.1}}
        """)
        #expect(place.country == .japan)
        #expect(place.states.isEmpty)
        #expect(place.regionLine == "Hokkaido")
        #expect(place.localNames == [LocalName(language: "ja", text: "知床国立公園")])
    }

    @Test("an unknown subdivision is dropped, never shown as a name")
    func unknownSubdivisionDropped() throws {
        let place = try decode("""
        {"id": "no-np-reisa", "name": "Reisa", "kind": "nationalPark", "country": "NO",
         "subdivisions": ["NO-54", "NO-55"], "centre": {"latitude": 69.6, "longitude": 21.6}}
        """)
        #expect(place.subdivisions.map(\.name) == ["Troms"])
    }

    @Test("a place across many prefectures gives the count")
    func manySubdivisionsCollapse() {
        let place = Place(
            id: "jp-np-setonaikai", name: "Setonaikai", designation: "National Park",
            kind: .nationalPark, states: [], centre: Coordinate(latitude: 34.3, longitude: 133),
            country: .japan,
            subdivisions: ["JP-26", "JP-27", "JP-28", "JP-30"].compactMap(Subdivision.named)
        )
        #expect(place.regionLine == "4 prefectures")
    }

    @Test("a place abroad with no zone keeps its country's time")
    func countryTimeZoneFallback() {
        let place = Place(
            id: "no-np-rondane", name: "Rondane", designation: "National Park",
            kind: .nationalPark, states: [], centre: Coordinate(latitude: 61.9, longitude: 9.8),
            country: .norway
        )
        #expect(UnigridsCalendar.timeZone(for: place).identifier == "Europe/Oslo")
    }
}

@Suite("Search folding")
struct SearchTextTests {
    @Test("names are found without their accents, letters or marks")
    func folding() {
        #expect(SearchText.fold("Øvre Dividal") == "ovre dividal")
        #expect(SearchText.fold("Færder") == "faerder")
        #expect(SearchText.fold("Kujū") == "kuju")
        #expect(SearchText.fold("Láhko") == "lahko")
        #expect(SearchText.fold("Hawaiʻi Volcanoes") == "hawaii volcanoes")
        #expect(SearchText.fold("ＡＢＣ") == "abc")
        #expect(SearchText.fold("しれとこ") == SearchText.fold("シレトコ"))
        #expect(SearchText.fold("Fuji-Hakone-Izu") == "fuji hakone izu")
        #expect(SearchText.fold("Sør-Spitsbergen") == "sor spitsbergen")
        #expect(SearchText.contains("Damtjønna – Grøtberget", "grotberget"))
        #expect(SearchText.contains("Lake Chūzenji", "chuzenji"))
    }

    @Test("a query matches inside a name, folded on both sides")
    func containment() {
        #expect(SearchText.contains("Øvre Pasvik", "ovre"))
        #expect(SearchText.contains("知床国立公園", "知床"))
        #expect(!SearchText.contains("Rondane", "jotun"))
        #expect(SearchText.contains("Rondane", "  "))
    }
}

@Suite("Tile maps for every country")
struct SubdivisionTileGridTests {
    @Test("every subdivision has one square, and no two share a cell", arguments: Country.allCases)
    func gridIsTotal(country: Country) {
        let grid = SubdivisionTileGrid.grid(for: country)
        let codes = grid.tiles.map(\.code)
        #expect(Set(codes) == Set(Subdivision.all(in: country).map(\.code)))
        #expect(Set(codes).count == codes.count)
        let cells = grid.tiles.map { "\($0.row),\($0.column)" }
        #expect(Set(cells).count == cells.count)
        #expect(grid.tiles.allSatisfy { $0.row < grid.rows && $0.column < grid.columns })
    }

    @Test("Japan's squares carry the prefectures' names in kanji")
    func japaneseLabels() {
        let grid = SubdivisionTileGrid.grid(for: .japan)
        #expect(grid.tiles.first { $0.code == "JP-01" }?.label == "北海道")
        #expect(grid.tiles.first { $0.code == "JP-47" }?.label == "沖縄")
        #expect(grid.labelLanguage == "ja")
    }
}

@Suite("Map regions")
struct MapRegionsTests {
    @Test("a reader opens on their own country only when its places ship")
    func homeCountry() {
        #expect(MapRegions.homeCountry(regionCode: "JP", among: [.unitedStates, .japan]) == .japan)
        #expect(MapRegions.homeCountry(regionCode: "JP", among: [.unitedStates]) == .unitedStates)
        #expect(MapRegions
            .homeCountry(regionCode: "GB", among: [.unitedStates, .norway]) == .unitedStates)
        #expect(MapRegions.homeCountry(regionCode: nil, among: [.norway]) == .unitedStates)
    }

    @Test("a saved view round-trips, and junk is refused")
    func savedView() throws {
        let box = MapRegions.home(.norway)
        let decoded = try #require(MapRegions.decode(MapRegions.encode(box)))
        #expect(abs(decoded.north - box.north) < 0.001 && abs(decoded.west - box.west) < 0.001)
        #expect(MapRegions.decode("") == nil)
        #expect(MapRegions.decode("1,2,3") == nil)
        #expect(MapRegions.decode("50,0,40,10") == nil)
    }

    @Test("every country's shortcuts open on its home view")
    func shortcutsStartHome() {
        for country in Country.allCases {
            #expect(MapRegions.shortcuts(in: country).first?.box == MapRegions.home(country))
        }
    }

    @Test("the map knows which country it is showing, and says nothing over open sea")
    func countryInView() {
        let all = Country.allCases
        let longyearbyen = Coordinate(latitude: 78.22, longitude: 15.65)
        #expect(MapRegions.country(at: longyearbyen, among: all) == .norway)
        #expect(MapRegions.country(at: Coordinate(latitude: 35.36, longitude: 138.73), among: all)
            == .japan)
        #expect(MapRegions.country(at: Coordinate(latitude: 63.1, longitude: -151), among: all)
            == .unitedStates)
        #expect(MapRegions.country(at: Coordinate(latitude: 40, longitude: -35), among: all) == nil)
        // A country without places is never the one in view.
        #expect(MapRegions.country(at: longyearbyen, among: [.unitedStates]) == nil)
    }
}
