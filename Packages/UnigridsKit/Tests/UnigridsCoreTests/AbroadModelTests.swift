import Foundation
import Testing
@testable import UnigridsCore

@Suite("Kinds of place abroad")
struct KindsAbroadTests {
    private func place(
        _ kind: PlaceKind,
        country: Country,
        in codes: [String],
        managedBy: String? = nil
    ) -> Place {
        Place(
            id: "x", name: "X", designation: "", kind: kind, states: [],
            centre: Coordinate(latitude: 0, longitude: 0), managedBy: managedBy,
            country: country, subdivisions: codes.compactMap(Subdivision.named)
        )
    }

    @Test("a quasi-national park is drawn as a state park is: a circle, in violet")
    func quasiNationalPark() {
        let park = place(.quasiNationalPark, country: .japan, in: ["JP-20"])
        #expect(park.siteType == .quasiNationalPark)
        #expect(park.tier == .statePark)
        #expect(park.agency == .prefecture)
        #expect(park.siteType.ink == .statePark)
        #expect(park.siteType.homeCountry == .japan)
    }

    @Test("Norway's landscapes and reserves are other public land: hexagons")
    func norwegianProtectedAreas() {
        let landscape = place(.protectedLandscape, country: .norway, in: ["NO-34"])
        let reserve = place(.natureReserve, country: .norway, in: ["NO-55"])
        #expect(landscape.tier == .federalSite && reserve.tier == .federalSite)
        #expect(landscape.siteType.ink == .conservation)
        #expect(reserve.siteType.ink == .refuge)
        #expect(landscape.siteType.group == .otherPublicLands)
        #expect(reserve.agency == .environmentAgencyNorway)
    }

    @Test("a sentence from the fields names the subdivision and who runs it")
    func factualSentences() {
        let reserve = place(
            .natureReserve, country: .norway, in: ["NO-34"],
            managedBy: "Statsforvalteren i Innlandet"
        )
        #expect(
            reserve.factualDescription
                == "A nature reserve in Innlandet, managed by Statsforvalteren i Innlandet."
        )
        let quasi = place(.quasiNationalPark, country: .japan, in: ["JP-20"])
        #expect(
            quasi.factualDescription == "A quasi-national park in Nagano, designated by "
                + "Japan's Ministry of the Environment and run by the prefecture."
        )
    }

    @Test("a national park is a national park, wherever it is")
    func nationalParksEverywhere() {
        let shiretoko = place(.nationalPark, country: .japan, in: ["JP-01"])
        #expect(shiretoko.siteType == .nationalPark)
        #expect(shiretoko.siteType.homeCountry == nil)
        #expect(shiretoko.tier.hasGuide)
    }
}

@Suite("Published trail grades")
struct TrailGradeTests {
    @Test("the Norwegian marking grades, and the one left ungraded")
    func norwegianGrades() {
        let bands: [String: TrailDifficulty] = [
            "G": .easy, "B": .moderate, "R": .strenuous, "S": .veryStrenuous,
        ]
        let labels = ["G": "Green", "B": "Blue", "R": "Red", "S": "Black", "I": "Not graded"]
        for grade in ["G", "B", "R", "S", "I", "X"] {
            let published = TrailGrade(system: .norwegianMarking, grade: grade)
            #expect(published.band == bands[grade], "\(grade)")
            #expect(published.label == labels[grade], "\(grade)")
        }
    }

    @Test("a Japanese grade files under the harder of its two scales")
    func japaneseGrades() {
        func band(_ grade: String) -> TrailDifficulty? {
            TrailGrade(system: .japaneseMountainGrading, grade: grade).band
        }
        #expect(band("1A") == .easy)
        #expect(band("3C") == .moderatelyStrenuous)
        #expect(band("9A") == .veryStrenuous)
        #expect(band("2E") == .veryStrenuous)
        #expect(band("11A") == nil)
        #expect(band("3F") == nil)
        let grade = TrailGrade(system: .japaneseMountainGrading, grade: "3C")
        #expect(grade.label == "Stamina 3, technical C")
    }

    @Test("a published grade replaces the estimate, and says so")
    func gradeReplacesEstimate() throws {
        let json = """
        {"id": "trail-no-jotunheimen-besseggen", "placeID": "no-np-jotunheimen",
         "name": "Besseggen", "lengthMetres": 14000, "gainMetres": 900,
         "publishedGrade": {"system": "norwegianMarking", "grade": "R"}}
        """
        let trail = try JSONDecoder().decode(Trail.self, from: Data(json.utf8))
        #expect(trail.estimatedDifficulty == .strenuous)
        #expect(!trail.isDifficultyEstimated)

        let ungraded = Trail(
            id: "t",
            placeID: "p",
            name: "T",
            lengthMetres: 5000,
            gainMetres: 100
        )
        #expect(ungraded.isDifficultyEstimated)
    }
}

@Suite("Facts abroad")
struct FactsAbroadTests {
    @Test("a fee shows its own currency, the reader's way, never converted")
    func feeCurrency() {
        let fuji = EntranceFee(
            title: "Climbing fee", cost: "¥4,000", amount: 4000, currencyCode: "JPY"
        )
        let us = fuji.displayCost(locale: Locale(identifier: "en_US"))
        #expect(us.contains("4,000") && us.contains("¥"), "\(us)")
        let free = EntranceFee(title: "Entry", cost: "Free", amount: 0, currencyCode: "NOK")
        #expect(free.displayCost() == "Free")
        let asPublished = EntranceFee(title: "Private vehicle", cost: "$35")
        #expect(asPublished.displayCost() == "$35")
    }

    @Test("an area published in hectares stays in hectares, or reads as acres in the US")
    func hectares() throws {
        let facts = PlaceFacts(areaHectares: 38636)
        #expect(!facts.isEmpty)
        let area = try #require(facts.area)
        let metric = UnigridsFormat.area(area, locale: Locale(identifier: "en_GB"))
        let imperial = UnigridsFormat.area(area, locale: Locale(identifier: "en_US"))
        #expect(metric.contains("38,636"), "\(metric)")
        #expect(imperial.contains("95,472"), "\(imperial)")
    }

    @Test("an area in acres still wins where both are given, as US data has it")
    func acresFirst() {
        let facts = PlaceFacts(areaAcres: 147_242.66, areaHectares: 1)
        #expect(facts.area?.unit == .acres)
    }

    @Test("huts are facilities; a document can say its language")
    func hutsAndDocuments() throws {
        #expect(POIKind.hut.isFacility && POIKind.hut.isCheckInTarget)
        #expect(!POIKind.sight.isFacility)
        let json = #"{"title": "Map", "url": "https://example.org/a.pdf", "language": "ja"}"#
        let document = try JSONDecoder().decode(ParkDocument.self, from: Data(json.utf8))
        #expect(document.language == "ja")
    }
}

@Suite("Guides and rail abroad")
struct GuideAndRailAbroadTests {
    @Test("a guide abroad carries how the park works, and huts make a panel")
    func panelsAbroad() throws {
        let json = #"{"placeID": "no-np-rondane", "story": ["S"], "howItWorks": ["H"]}"#
        let guide = try JSONDecoder().decode(GuideContent.self, from: Data(json.utf8))
        #expect(guide.howItWorks == ["H"])
        let panels = guide.panels(
            placeHasFacts: false, sightCount: 0, visitorCentreCount: 0, hasTrails: false,
            hutCount: 3
        )
        #expect(panels == [.story, .howItWorks, .huts])
    }

    @Test("a transport file with no layers abroad still decodes")
    func transportDecodesOldFiles() throws {
        let old = #"{"interstates": [], "usHighways": [], "amtrakRoutes": [], "#
            + #""amtrakStations": []}"#
        let network = try JSONDecoder().decode(TransportNetwork.self, from: Data(old.utf8))
        #expect(network.railStations.isEmpty && network.isEmpty)
    }

    @Test("a park's nearest station is in its own country")
    func stationsStayInTheirCountry() {
        let park = Place(
            id: "no-np-ovre-pasvik", name: "Øvre Pasvik", designation: "National Park",
            kind: .nationalPark, states: [], centre: Coordinate(latitude: 69.1, longitude: 29.1),
            country: .norway
        )
        let network = TransportNetwork(railStations: [
            RailStation(
                code: "osm:node/1", name: "Across the border",
                location: Coordinate(latitude: 69.1, longitude: 29.4), country: .japan
            ),
            RailStation(
                code: "osm:node/2", name: "Narvik",
                location: Coordinate(latitude: 68.44, longitude: 17.43), country: .norway,
                lines: ["Ofotbanen"]
            ),
        ])
        #expect(network.trainAccess(to: park, boundary: nil) == nil)
        let narvik = Place(
            id: "no-np-x", name: "X", designation: "", kind: .nationalPark, states: [],
            centre: Coordinate(latitude: 68.5, longitude: 17.6), country: .norway
        )
        let access = network.trainAccess(to: narvik, boundary: nil)
        #expect(access?.station.name == "Narvik")
        #expect(access?.services == ["Ofotbanen"])
    }
}
