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

    @Test("the dataset loads and says the pipeline built it")
    func manifest() {
        #expect(store.manifest.version >= 2)
        #expect(store.manifest.provenance == .pipeline)
        #expect(store.manifest.note?.isEmpty == false)
    }

    @Test("every tier is on the map")
    func tiers() {
        let byTier = Dictionary(grouping: store.places, by: \.tier)
        #expect(byTier[.nationalPark]?.count == 63)
        #expect((byTier[.npsUnit]?.count ?? 0) >= 300)
        #expect((byTier[.statePark]?.count ?? 0) >= 50)
        #expect((byTier[.federalSite]?.count ?? 0) >= 15)
        #expect(Set(store.places.map(\.id)).count == store.places.count)
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
            // The remote Pacific and Caribbean refuges lie in no state or territory the
            // Census draws; they are the only places allowed to have none.
            #expect(
                !place.states.isEmpty || place.kind == .wildlifeRefuge,
                "\(place.name) has no state"
            )
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

    /// A guide that fails to decode does not crash anything — the store skips it and the
    /// park quietly loses its guide. This is the test that notices.
    @Test("every national park has a guide with real content")
    func everyParkHasAGuide() throws {
        for place in store.nationalParks {
            let guide = try #require(store.guide(for: place.id), "missing guide for \(place.name)")
            #expect(guide.story.count >= 3, "\(place.name) story is thin")
            #expect(!guide.chronology.isEmpty, "\(place.name) has no chronology")
            #expect(!guide.planYourVisit.isEmpty, "\(place.name) has no plan-your-visit")
            #expect(!guide.safety.isEmpty, "\(place.name) has no safety notes")
            #expect(!guide.sources.isEmpty, "\(place.name) cites no source")
            #expect(guide.hero != nil, "\(place.name) has no hero photograph")
        }
    }

    @Test("every national park has a written overview and sights on its map")
    func everyParkHasAnOverview() {
        for place in store.nationalParks {
            #expect(place.summarySource == "Unigrids", "\(place.name) has no written summary")
            #expect((place.summary?.count ?? 0) > 80, "\(place.name) summary is thin")
            // Roadless parks such as Kobuk Valley have only a handful of named sights.
            #expect(store.sights(in: place.id).count >= 3, "\(place.name) has too few sights")
            #expect(
                !store.visitorCentres(in: place.id).isEmpty,
                "\(place.name) has no visitor centre"
            )
        }
    }

    @Test("every curated state park, monument and refuge has a written overview")
    func curatedSitesHaveOverviews() {
        let stateParks = store.places.filter { $0.tier == .statePark }
        #expect(stateParks.count >= 50)
        for place in stateParks {
            #expect((place.summary?.count ?? 0) > 60, "\(place.name) has no summary")
            #expect(place.summarySource == "Unigrids")
        }
        let federal = store.places.filter { $0.tier == .federalSite }
        let written = federal.filter { $0.summary != nil }
        #expect(written.count >= 25)
        // The rest of the public lands carry no prose by design: nobody wrote any, and
        // the sources publish none. What is there must say who wrote it.
        for place in written {
            #expect((place.summary?.count ?? 0) > 60, "\(place.name) summary is thin")
            #expect(place.summarySource == "Unigrids")
        }
    }

    @Test("sight ranks are unique within a park, so the order is unambiguous")
    func sightRanksAreUnique() {
        for place in store.places {
            let ranks = store.sights(in: place.id).map(\.rank)
            #expect(Set(ranks).count == ranks.count, "\(place.name) has duplicate ranks")
        }
    }

    @Test("every national park carries its sourced figures")
    func nationalParkFacts() throws {
        for park in store.nationalParks {
            #expect(park.facts.establishedYear != nil, "\(park.name) has no establishment year")
            #expect(park.facts.areaAcres != nil, "\(park.name) has no area")
            #expect(park.facts.annualVisits != nil, "\(park.name) has no visitation")
            #expect(park.facts.annualVisitsYear == 2025)
        }
        // Spot checks against the NPS's own published figures: the 2025 visitation release
        // and the 2023 acreage report. A change here is a data change worth a look.
        let zion = try #require(store.place("np-zion"))
        #expect(zion.facts.establishedYear == 1919)
        #expect(zion.facts.annualVisits == 4_984_525)
        let yellowstone = try #require(store.place("np-yellowstone"))
        #expect(yellowstone.facts.establishedYear == 1872)
        #expect((yellowstone.facts.areaAcres ?? 0).rounded() == 2_219_791)
    }

    @Test("figures not in the sources stay absent rather than guessed")
    func absentFiguresStayAbsent() {
        // Other NPS units come from the NPS API, which publishes no establishment year or
        // visitation; an invented one would reach the reader as a fact.
        for place in store.places where place.tier == .npsUnit {
            #expect(place.facts.establishedYear == nil)
            #expect(place.facts.annualVisits == nil)
        }
    }

    @Test("outlines decode, sit where their places are, and stay off the antimeridian")
    func outlines() throws {
        #expect(store.boundaries.count >= 450)
        for park in store.nationalParks {
            let boundary = try #require(store.boundary(for: park.id), "\(park.name) has no outline")
            #expect(boundary.pointCount >= 4)
            #expect(
                boundary.extent.expanded(by: 0.25).contains(park.centre),
                "\(park.name)'s pin is far from its outline"
            )
        }
        for (id, boundary) in store.boundaries {
            // The hit test is planar in degrees; an outline spanning the antimeridian
            // would break it (BoundaryPolygon.contains).
            #expect(boundary.extent.east - boundary.extent.west < 180, "\(id) wraps the globe")
        }
    }

    @Test("a tap inside an outline finds its place")
    func hitTesting() {
        // The Zion Canyon floor, and the middle of Yellowstone Lake.
        #expect(store.place(at: Coordinate(latitude: 37.25, longitude: -112.95))?.id == "np-zion")
        #expect(
            store.place(at: Coordinate(latitude: 44.45, longitude: -110.35))?.id == "np-yellowstone"
        )
        // Kansas has no national park.
        let kansas = store.place(
            at: Coordinate(latitude: 38.5, longitude: -98.5),
            among: store.nationalParks
        )
        #expect(kansas == nil)
    }

    @Test("every national park has a bundled NPS photograph that resolves")
    func photographs() throws {
        for park in store.nationalParks {
            let guide = try #require(store.guide(for: park.id))
            let hero = try #require(guide.hero, "\(park.name) has no hero photograph")
            #expect(hero.isPublicDomain)
            #expect(hero.credit.uppercased().hasPrefix("NPS")
                || hero.credit.lowercased().hasPrefix("national park service"))
            let url = try #require(store.imageURL(for: hero))
            #expect(url.isFileURL, "\(park.name)'s hero is not bundled")
            for image in guide.gallery {
                #expect(store.imageURL(for: image)?.isFileURL == true)
            }
        }
    }

    /// Every bundled photograph ships in the app, so a stray file is dead weight. This
    /// catches the conflict copies ("name 2.jpg") an iCloud-synced checkout leaves behind
    /// when the pipeline replaces images in place.
    @Test("the bundled images are exactly the photographs the data refers to")
    func noStrayImages() throws {
        var referenced: Set<String> = []
        for place in store.places {
            if let name = place.image?.assetName {
                referenced.insert(name)
            }
            if let guide = store.guide(for: place.id) {
                for image in [guide.hero].compactMap(\.self) + guide.gallery {
                    if let name = image.assetName {
                        referenced.insert(name)
                    }
                }
            }
            for poi in store.pointsOfInterest(in: place.id) {
                if let name = poi.image?.assetName {
                    referenced.insert(name)
                }
            }
        }
        let park = try #require(store.nationalParks.first)
        let hero = try #require(store.guide(for: park.id)?.hero)
        let folder = try #require(store.imageURL(for: hero)).deletingLastPathComponent()
        let bundled = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        let stray = bundled.subtracting(referenced).sorted()
        let missing = referenced.subtracting(bundled).sorted()
        #expect(stray.isEmpty, "unreferenced images: \(stray.prefix(5))")
        #expect(missing.isEmpty, "missing images: \(missing.prefix(5))")
    }

    @Test("reused photographs of other places carry a credit and a reusable licence")
    func otherPhotographs() {
        for place in store.places where place.tier != .nationalPark {
            guard let image = place.image else { continue }
            #expect(!image.credit.isEmpty)
            #expect(
                image.isPublicDomain || image.licence != nil,
                "\(place.name) photo has no licence"
            )
        }
    }

    @Test("search finds a park by name, by prefix and by state")
    func search() {
        #expect(store.search("zion").first?.id == "np-zion")
        #expect(store.search("yellow").first?.id == "np-yellowstone")
        #expect(store.search("Maine").contains { $0.id == "np-acadia" })
        #expect(store.search("UT").contains { $0.id == "np-zion" })
        #expect(store.search("lincoln").contains { $0.id == "nps-linc" })
        #expect(store.searchPointsOfInterest("visitor").isEmpty == false)
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

    @Test("nearest returns places in distance order")
    func nearest() {
        // The Zion Canyon Visitor Center, inside the park.
        let visitorCentre = Coordinate(latitude: 37.2, longitude: -112.987)
        let nearest = store.nearest(to: visitorCentre, limit: 3)
        #expect(nearest.first?.id == "np-zion")
        #expect(nearest.count == 3)
        // Springdale, outside it: of the national parks, Zion is still nearest.
        let springdale = Coordinate(latitude: 37.18, longitude: -113.0)
        #expect(store.nearest(to: springdale, limit: 1, tiers: [.nationalPark]).first?.id
            == "np-zion")
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
