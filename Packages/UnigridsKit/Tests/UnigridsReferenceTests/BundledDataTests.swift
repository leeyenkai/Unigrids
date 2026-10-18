import Foundation
import Testing
import UnigridsCore
@testable import UnigridsReference

/// These tests are the seed data's only reviewer. They do not check that a figure is
/// *right* — nothing in the repository can — but they do catch the mistakes that would
/// otherwise reach a user as a broken screen: a dangling id, a missing guide, a park
/// counted twice, a coordinate in the wrong hemisphere.
@Suite("Bundled reference data")
struct BundledDataTests {
    private let store: BundledReferenceStore

    init() throws {
        store = try BundledReferenceStore.bundled()
    }

    @Test("the dataset loads and declares itself a seed")
    func manifest() {
        #expect(store.manifest.version >= 1)
        #expect(store.manifest.provenance == .seed)
        #expect(store.manifest.note?.isEmpty == false)
    }

    @Test("all 63 national parks are present, each once")
    func sixtyThreeParks() {
        let parks = store.nationalParks
        #expect(parks.count == 63)
        #expect(Set(parks.map(\.id)).count == 63)
        #expect(Set(parks.map(\.name)).count == 63)
    }

    @Test("every place has an id, a state and a plausible coordinate")
    func placesAreWellFormed() {
        for place in store.places {
            #expect(!place.id.rawValue.isEmpty)
            #expect(!place.name.isEmpty)
            #expect(!place.states.isEmpty, "\(place.name) has no state")
            #expect(
                (-90.0 ... 90.0).contains(place.centre.latitude),
                "\(place.name) latitude out of range"
            )
            #expect(
                (-180.0 ... 180.0).contains(place.centre.longitude),
                "\(place.name) longitude out of range"
            )
        }
    }

    @Test("every point of interest belongs to a place that exists")
    func poiPlaceIDsResolve() {
        for place in store.places {
            for poi in store.pointsOfInterest(in: place.id) {
                #expect(store.place(poi.placeID) != nil)
            }
        }
    }

    @Test("every theme tag on a place resolves to a theme")
    func themeIDsResolve() {
        for place in store.places {
            for theme in place.themes {
                #expect(store.theme(theme) != nil, "\(place.name) -> \(theme)")
            }
        }
    }

    @Test("each pilot park has a guide with real content")
    func pilotGuides() throws {
        let pilot: [UnigridsID] = [
            "np-zion", "np-acadia", "np-yellowstone", "np-great-smoky-mountains",
        ]
        for id in pilot {
            let place = try #require(store.place(id), "missing place \(id)")
            let guide = try #require(store.guide(for: id), "missing guide for \(place.name)")
            #expect(guide.story.count >= 3, "\(place.name) story is thin")
            #expect(!guide.chronology.isEmpty)
            #expect(!guide.planYourVisit.isEmpty)
            #expect(!guide.safety.isEmpty)
            #expect(!guide.sources.isEmpty, "\(place.name) cites no source")
        }
    }

    @Test("each pilot park has sights, a visitor centre and somewhere to stamp")
    func pilotPointsOfInterest() {
        let pilot: [UnigridsID] = [
            "np-zion", "np-acadia", "np-yellowstone", "np-great-smoky-mountains",
        ]
        for id in pilot {
            #expect(store.sights(in: id).count >= 5, "\(id) has too few sights")
            #expect(!store.visitorCentres(in: id).isEmpty, "\(id) has no visitor centre")
            #expect(!store.stampLocations(in: id).isEmpty, "\(id) has no stamp location")
        }
    }

    @Test("sight ranks are unique within a park, so the order is unambiguous")
    func sightRanksAreUnique() {
        for place in store.places {
            let ranks = store.sights(in: place.id).map(\.rank)
            #expect(Set(ranks).count == ranks.count, "\(place.name) has duplicate ranks")
        }
    }

    @Test("a pilot park's facts are filled, and the rest are honestly empty")
    func factsOnlyWherePresent() throws {
        let zion = try #require(store.place("np-zion"))
        #expect(!zion.facts.isEmpty)
        #expect(zion.facts.establishedYear == 1919)
        #expect(zion.facts.highestElevationMetres != nil)

        // The other 59 parks carry no at-a-glance figures. An absent figure is correct;
        // a plausible invented one would reach the user as a fact.
        let grandCanyon = try #require(store.place("np-grand-canyon"))
        #expect(grandCanyon.facts.isEmpty)
    }

    @Test("search finds a park by name, by prefix and by state")
    func search() {
        #expect(store.search("zion").first?.id == "np-zion")
        #expect(store.search("yellow").first?.id == "np-yellowstone")
        #expect(store.search("Maine").contains { $0.id == "np-acadia" })
        #expect(store.search("UT").contains { $0.id == "np-zion" })
        #expect(store.search("   ").isEmpty)
    }

    @Test("every park falls in a passport region")
    func passportRegions() {
        let grouped = store.placesByPassportRegion()
        #expect(grouped.values.map(\.count).reduce(0, +) == store.places.count)
        // Nine regions exist; the pilot seed need not fill all of them, but the parks
        // should spread over most of the country.
        #expect(grouped.keys.count >= 6)
    }

    @Test("the trail catalogue is empty, and that is the expected state")
    func trailsAreNotYetPopulated() {
        // Trails land in 1.0.0 (docs/mvp-scope.md). An absent trails.json must load
        // cleanly rather than throw, which is what this asserts.
        #expect(store.trails(in: "np-zion").isEmpty)
    }

    @Test("nearest returns places in distance order")
    func nearest() {
        // Springdale, Utah, at Zion's south entrance.
        let springdale = Coordinate(latitude: 37.19, longitude: -112.99)
        let nearest = store.nearest(to: springdale, limit: 3)
        #expect(nearest.first?.id == "np-zion")
        #expect(nearest.count == 3)
    }

    @Test("an empty store is usable rather than a crash")
    func emptyStore() {
        let empty = BundledReferenceStore.empty()
        #expect(empty.places.isEmpty)
        #expect(empty.place("np-zion") == nil)
        #expect(empty.search("zion").isEmpty)
        #expect(empty.manifest.version == 0)
    }
}
