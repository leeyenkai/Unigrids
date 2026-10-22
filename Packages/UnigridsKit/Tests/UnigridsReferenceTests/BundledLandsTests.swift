import Foundation
import Testing
import UnigridsCore
@testable import UnigridsReference

/// The dataset beyond the parks themselves: the other public lands, byways, the road and
/// rail layers, the trail catalogue, brochures and climate.
@Suite("Bundled lands, trails and layers")
struct BundledLandsTests {
    private let store: BundledReferenceStore

    init() throws {
        store = try BundledReferenceStore.bundled()
    }

    @Test("the other public lands are on the map, every kind of them")
    func otherPublicLands() {
        let byType = Dictionary(grouping: store.places, by: \.siteType)
        #expect((byType[.nationalForest]?.count ?? 0) >= 150)
        #expect((byType[.nationalGrassland]?.count ?? 0) >= 18)
        #expect((byType[.wildlifeRefuge]?.count ?? 0) >= 500)
        #expect((byType[.conservationArea]?.count ?? 0) >= 15)
        #expect((byType[.naturalLandmark]?.count ?? 0) >= 500)
        #expect((byType[.scenicByway]?.count ?? 0) >= 150)
        // Every type in the key has places behind it.
        for type in SiteType.allCases {
            #expect(byType[type]?.isEmpty == false, "no \(type.name) in the dataset")
        }
    }

    @Test("forests, grasslands and refuges are outlined; landmarks are points")
    func outlinesByKind() {
        for place in store.places {
            switch place.kind {
            case .nationalForest, .nationalGrassland, .wildlifeRefuge:
                #expect(store.boundary(for: place.id) != nil, "\(place.name) has no outline")
            case .naturalLandmark:
                #expect(store.boundary(for: place.id) == nil)
            default:
                break
            }
        }
    }

    @Test("every byway has a route, and its pin sits on it")
    func bywayRoutes() throws {
        let byways = store.places.filter { $0.kind == .scenicByway }
        #expect(!byways.isEmpty)
        for byway in byways {
            let route = try #require(store.route(for: byway.id), "\(byway.name) has no route")
            #expect(!route.paths.isEmpty)
            #expect(route.distance(to: byway.centre) < 2000, "\(byway.name) pin is off its road")
        }
    }

    @Test("the transport network loads, with every layer populated")
    func transportNetwork() throws {
        let network = try store.transportNetwork()
        #expect(network.interstates.count >= 200)
        #expect(network.usHighways.count >= 200)
        #expect(network.amtrakRoutes.count >= 40)
        #expect(network.amtrakStations.count >= 400)
        #expect(network.interstates.contains { $0.name == "I-80" })
        #expect(network.amtrakRoutes.contains { $0.name == "Empire Builder" })
        for line in network.interstates + network.usHighways + network.amtrakRoutes {
            #expect(!line.paths.isEmpty, "\(line.name) has no geometry")
        }
        // Glacier's Amtrak stop is the reason to draw the railway at all.
        let glacier = try #require(store.place("np-glacier"))
        #expect(network.amtrakRoutes(near: glacier.centre, within: 60000)
            .contains { $0.name == "Empire Builder" })
    }

    @Test("the trail catalogue covers the national parks, every trail drawable")
    func trails() {
        let all = store.allTrails
        #expect(all.count >= 2500)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.placeID)).count >= 50)
        for trail in all {
            #expect(
                store.place(trail.placeID)?.tier == .nationalPark,
                "\(trail.name) is not in a park"
            )
            #expect(!trail.paths.isEmpty, "\(trail.name) has no line")
            #expect(trail.lengthMetres > 0)
            if let gain = trail.gainMetres {
                #expect(gain >= 0)
                #expect((trail.highPointMetres ?? 0) >= (trail.lowPointMetres ?? 0))
                #expect(!trail.profile.isEmpty)
            }
            for sight in trail.sightIDs {
                #expect(store.sights(in: trail.placeID).contains { $0.id == sight })
            }
        }
        // Spot check: Zion's Watchman Trail, a short climb from the visitor centre.
        let watchman = store.trails(in: "np-zion").first { $0.name == "Watchman Trail" }
        #expect(watchman != nil)
        #expect((watchman?.climbMetres ?? 0) > 100)
    }

    @Test("brochure links and climate decode where the dataset has them")
    func documentsAndClimate() throws {
        let zion = try #require(store.documents(for: "np-zion"))
        #expect(zion.page != nil)
        let climate = try #require(store.climate(for: "np-zion"))
        #expect(climate.months.count == 12)
        let july = climate.months[6]
        #expect(july.highCelsius > july.lowCelsius)
        #expect(july.highCelsius > (climate.months[0].highCelsius))
    }

    @Test("the whole dataset loads in reasonable time")
    func loadTime() throws {
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try BundledReferenceStore.bundled() }
        // A debug build decodes several times slower than the release build users run.
        #expect(elapsed < .seconds(4), "loading took \(elapsed)")
    }
}
