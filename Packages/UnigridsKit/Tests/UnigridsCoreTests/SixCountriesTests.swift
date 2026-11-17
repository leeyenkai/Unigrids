import Foundation
import Testing
@testable import UnigridsCore

/// New Zealand, Australia and Canada join the model (ADR 0014): their divisions, the
/// zones their places keep, their books and the marks their stamps print.
@Suite("New Zealand, Australia and Canada")
struct SixCountriesTests {
    private func place(
        _ id: String, _ country: Country, _ codes: [String], at coordinate: Coordinate
    ) -> Place {
        Place(
            id: UnigridsID(id), name: id, designation: "National Park", kind: .nationalPark,
            states: [], centre: coordinate, country: country,
            subdivisions: codes.compactMap(Subdivision.named)
        )
    }

    @Test("each country's divisions are all there", arguments: [
        (Country.newZealand, 17), (Country.australia, 12), (Country.canada, 13),
    ])
    func subdivisionCounts(country: Country, expected: Int) {
        #expect(Subdivision.all(in: country).count == expected)
        #expect(Subdivision.all(in: country).allSatisfy { $0.country == country })
    }

    @Test("a place keeps its state's or province's zone when its record names none")
    func zonesBySubdivision() {
        let cases: [(Place, String)] = [
            (
                place(
                    "au-np-kakadu",
                    .australia,
                    ["AU-NT"],
                    at: .init(latitude: -12.9, longitude: 132.5)
                ),
                "Australia/Darwin"
            ),
            (
                place(
                    "ca-np-banff",
                    .canada,
                    ["CA-AB"],
                    at: .init(latitude: 51.5, longitude: -116)
                ),
                "America/Edmonton"
            ),
            (
                place(
                    "ca-np-terra-nova",
                    .canada,
                    ["CA-NL"],
                    at: .init(latitude: 48.5, longitude: -54)
                ),
                "America/St_Johns"
            ),
            (
                place(
                    "nz-np-tongariro",
                    .newZealand,
                    ["NZ-MWT"],
                    at: .init(latitude: -39.2, longitude: 175.6)
                ),
                "Pacific/Auckland"
            ),
            (
                place(
                    "nz-cp-chathams",
                    .newZealand,
                    ["NZ-CIT"],
                    at: .init(latitude: -44, longitude: -176.5)
                ),
                "Pacific/Chatham"
            ),
        ]
        for (place, zone) in cases {
            #expect(UnigridsCalendar.timeZone(for: place).identifier == zone)
        }
    }

    @Test("a stamp's foot names the state or province by its short code abroad")
    func stampMarks() {
        #expect(place(
            "au-np-kakadu",
            .australia,
            ["AU-NT"],
            at: .init(latitude: -12.9, longitude: 132.5)
        )
        .stampMark == "NT")
        #expect(place("ca-np-banff", .canada, ["CA-AB"], at: .init(latitude: 51.5, longitude: -116))
            .stampMark == "AB")
        #expect(place(
            "nz-np-fiordland",
            .newZealand,
            ["NZ-STL"],
            at: .init(latitude: -45.4, longitude: 167.7)
        )
        .stampMark == "Southland")
    }

    @Test("each new book has its regions, and its places their own national park system")
    func books() {
        #expect(PassportRegion.regions(in: .newZealand).count == 3)
        #expect(PassportRegion.regions(in: .australia).count == 8)
        #expect(PassportRegion.regions(in: .canada).count == 6)
        for country in [Country.newZealand, .australia, .canada] {
            #expect(PassportRegion.fallback(in: country).country == country)
        }
    }

    @Test("a state's national park without a guide sits in the state tier")
    func stateNationalPark() {
        #expect(PlaceKind.stateNationalPark.tier == .statePark)
        #expect(PlaceKind.provincialPark.tier == .statePark)
        #expect(PlaceKind.conservationPark
            .defaultAgency(in: .newZealand) == .conservationDepartmentNZ)
        #expect(PlaceKind.nationalPark.defaultAgency(in: .canada) == .parksCanada)
        #expect(PlaceKind.provincialPark.defaultAgency(in: .canada) == .provincialAgency)
    }

    @Test("each book prints its date its own way")
    func dateLines() throws {
        let utc = UnigridsCalendar.gregorian(.gmt)
        let date = try #require(utc.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 7,
            hour: 12
        )))
        func line(_ country: Country) -> String {
            StampFace(
                siteName: "x", date: date, stateCode: "x", region: .fallback(in: country),
                country: country, seed: 1, isVerifiedOnSite: false, calendar: utc
            ).dateLine()
        }
        #expect(line(.newZealand) == "07.11.2026")
        #expect(line(.australia) == "07 NOV 2026")
        #expect(line(.canada) == "2026-11-07")
    }

    @Test("southern Ontario and the Chathams open on their own country's map")
    func mapCountry() {
        let all = Country.allCases
        #expect(MapRegions
            .country(at: .init(latitude: 43.65, longitude: -79.38), among: all) == .canada)
        #expect(MapRegions
            .country(at: .init(latitude: 39.7, longitude: -105), among: all) == .unitedStates)
        #expect(MapRegions
            .country(at: .init(latitude: -44, longitude: -176.5), among: all) == .newZealand)
        #expect(MapRegions
            .country(at: .init(latitude: -25.3, longitude: 131.0), among: all) == .australia)
        #expect(MapRegions.world.contains(.init(latitude: -46.9, longitude: 168.1)))
    }
}

@Suite("New Zealand's track categories")
struct TrackCategoryTests {
    @Test("DOC's six categories read as published and into the bands; others are unsaid")
    func categories() {
        let milford = TrailGrade(
            system: .newZealandTrackCategory,
            grade: "Intermediate tramping track"
        )
        #expect(milford.label == "Intermediate tramping track")
        #expect(milford.band == .moderatelyStrenuous)
        #expect(TrailGrade(system: .newZealandTrackCategory, grade: "Expert route")
            .band == .veryStrenuous)
        let unknown = TrailGrade(system: .newZealandTrackCategory, grade: "Great Walk")
        #expect(unknown.label == nil && unknown.band == nil)
    }

    @Test("Parks Canada's four ratings read as published and into the bands")
    func parksCanada() {
        let grades = ["Easy", "Moderate", "Difficult", "Most difficult"].map {
            TrailGrade(system: .parksCanadaDifficulty, grade: $0)
        }
        #expect(grades.map(\.label) == ["Easy", "Moderate", "Difficult", "Most difficult"])
        #expect(grades.map(\.band) == [.easy, .moderate, .strenuous, .veryStrenuous])
        #expect(TrailGrade(system: .parksCanadaDifficulty, grade: "Expert").band == nil)
    }
}
