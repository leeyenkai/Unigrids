import Foundation
import Testing
import UnigridsCore
@testable import UnigridsReference

/// The places abroad, held to the invariants ADR 0013 sets: none of the US fallbacks
/// (a state's region, the NPS, a state's time zone) may fill a gap in their records.
/// Both countries ship, so every check is strict.
@Suite("Bundled data abroad")
struct BundledAbroadTests {
    private let store: BundledReferenceStore

    init() throws {
        store = try SharedBundle.store.get()
    }

    private func places(in country: Country) -> [Place] {
        store.places.filter { $0.country == country }
    }

    @Test("each country's national parks are all there, once", arguments: [
        (Country.japan, 35), (Country.norway, 48), (Country.newZealand, 13),
    ])
    func parkCounts(country: Country, expected: Int) {
        let parks = store.nationalParks.filter { $0.country == country }
        #expect(parks.count == expected)
        #expect(Set(parks.map(\.id)).count == expected)
    }

    @Test("each country's second tier ships whole", arguments: [
        (PlaceKind.quasiNationalPark, 58), (PlaceKind.protectedLandscape, 195),
        (PlaceKind.conservationPark, 49),
    ])
    func secondTier(kind: PlaceKind, expected: Int) {
        #expect(store.places.count { $0.kind == kind } == expected)
        // Norway's reserves are those of 10 km² or more, a count the data decides.
        #expect(store.places.count { $0.kind == .natureReserve } > 150)
    }

    @Test("every national park abroad has the full guide a US park has")
    func fullGuides() throws {
        for park in store.nationalParks where park.country != .unitedStates {
            #expect(store.boundary(for: park.id) != nil, "\(park.name) has no outline")
            #expect(park.summary?.isEmpty == false, "\(park.name) has no summary")
            #expect(park.facts.establishedYear != nil, "\(park.name) has no founding year")
            let guide = try #require(store.guide(for: park.id), "\(park.name) has no guide")
            #expect(guide.story.count >= 2, "\(park.name) has a thin story")
            #expect(store.sights(in: park.id).count >= 3, "\(park.name) has under 3 sights")
            #expect(!guide.chronology.isEmpty, "\(park.name) has no chronology")
            #expect(!guide.sources.isEmpty, "\(park.name) cites no source")
            // Every photograph names who took it and under what licence; none abroad is
            // public domain by default.
            for image in [guide.hero].compactMap(\.self) + guide.gallery {
                #expect(!image.credit.isEmpty, "\(park.name): \(image.id) has no credit")
                #expect(
                    image.isPublicDomain || image.licence?.isEmpty == false,
                    "\(park.name): \(image.id) has no licence"
                )
            }
        }
    }

    @Test("Japan's first three parks are of 1934, and the idea's dates hold")
    func foundingParks() throws {
        for id in ["jp-np-setonaikai", "jp-np-unzen-amakusa", "jp-np-kirishima-kinkowan"] {
            let park = try #require(store.place(UnigridsID(id)))
            #expect(park.facts.establishedYear == 1934, "\(id)")
        }
        let earliest = store.nationalParks.filter { $0.country == .norway }
            .compactMap(\.facts.establishedYear).min()
        #expect(earliest == 1962)
    }

    @Test("an Arctic or island park says how it is reached")
    func reachedBy() {
        for park in store.nationalParks where park.subdivisions.contains(where: {
            $0.code == "NO-21"
        }) {
            #expect(park.reachedBy?.contains("Longyearbyen") == true, "\(park.name)")
        }
        #expect(store.place("jp-np-ogasawara")?.reachedBy?.contains("Tokyo") == true)
    }

    @Test("a place abroad carries its own country's region, zone and agency", arguments: [
        Country.japan, Country.norway, Country.newZealand,
    ])
    func noUSFallbacks(country: Country) {
        for place in places(in: country) {
            #expect(place.states.isEmpty, "\(place.name) has a US state")
            #expect(!place.subdivisions.isEmpty, "\(place.name) has no subdivision")
            #expect(place.passportRegion?.country == country, "\(place.name) region")
            #expect(place.timeZoneID != nil, "\(place.name) has no time zone")
            #expect(place.agency != .nps, "\(place.name) is filed under the NPS")
            #expect(Country.inferred(from: place.id) == country, "\(place.id) is not namespaced")
        }
    }

    @Test("a national park abroad shows its own name in its own language", arguments: [
        Country.japan, Country.norway,
    ])
    func localNames(country: Country) {
        for park in store.nationalParks where park.country == country {
            #expect(!park.localNames.isEmpty, "\(park.name) has no local name")
        }
    }

    @Test("guides abroad say how the park works")
    func howItWorks() throws {
        for park in store.nationalParks where park.country != .unitedStates {
            let guide = try #require(store.guide(for: park.id))
            #expect(!guide.howItWorks.isEmpty, "\(park.name) has no how-it-works panel")
            #expect(guide.weather != nil || guide.directions != nil, "\(park.name) is thin")
        }
    }

    @Test("Rondane is Norway's first national park, of 1962")
    func rondane() throws {
        let rondane = try #require(store.place("no-np-rondane"))
        #expect(rondane.facts.establishedYear == 1962)
        #expect(rondane.passportRegion == .easternNorway)
    }

    @Test("search finds a park abroad without its marks, and by its own name")
    func searchAbroad() {
        #expect(store.search("ovre dividal").first?.id == "no-np-ovre-dividal")
        #expect(store.search("知床").contains { $0.id == "jp-np-shiretoko" })
        #expect(store.search("kuju").contains { $0.id == "jp-np-aso-kuju" })
    }
}

extension BundledAbroadTests {
    /// The stations a reader travels from, which Overpass's partial answers once left out:
    /// Japan's OpenStreetMap is now read whole from a Geofabrik extract.
    @Test("Japan's main stations are on the rail network, with their lines")
    func mainStations() throws {
        let network = try store.transportNetwork()
        let japan = network.railStations.filter { $0.country == .japan }
        for name in ["Tokyo", "Sapporo", "Shin-Osaka", "Hakata", "Matsumoto"] {
            let station = japan.first { $0.name.contains(name) && !($0.lines ?? []).isEmpty }
            #expect(station != nil, "\(name) is missing")
        }
    }

    /// Tongariro, gifted in 1887 and made a park by the Act of 1894, is the founding
    /// year the guide gives; DOC's track categories ride on its tracks.
    @Test("New Zealand's parks carry DOC's huts, graded tracks and te reo names")
    func newZealand() throws {
        let tongariro = try #require(store.place("nz-np-tongariro"))
        #expect(tongariro.timeZoneID == "Pacific/Auckland")
        #expect(tongariro.agency == .conservationDepartmentNZ)
        let parks = store.nationalParks.filter { $0.country == .newZealand }
        let withHuts = parks.count { park in
            store.pointsOfInterest(in: park.id).contains { $0.kind == .hut }
        }
        #expect(withHuts == parks.count)
        let graded = store.trails(in: tongariro.id).filter {
            $0.publishedGrade?.system == .newZealandTrackCategory
        }
        #expect(!graded.isEmpty)
        let westland = try #require(store.place("nz-np-westland-tai-poutini"))
        #expect(westland.localNames.contains { $0.language == "mi" })
    }

    @Test("most of Japan's national parks list their huts")
    func japaneseHuts() {
        let parks = store.nationalParks.filter { $0.country == .japan }
        let withHuts = parks.count { park in
            store.pointsOfInterest(in: park.id).contains { $0.kind == .hut }
        }
        #expect(withHuts >= 15)
    }
}
