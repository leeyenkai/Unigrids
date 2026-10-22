import Foundation
import Testing
@testable import UnigridsCore

@Suite("Site types")
struct SiteTypeTests {
    @Test(
        "NPS designations fall into the type a reader would expect",
        arguments: [
            ("National Monument", SiteType.nationalMonument),
            ("National Monument & Preserve", .nationalMonument),
            ("National Monument and Historic Shrine", .nationalMonument),
            ("National Historic Site", .historicSite),
            ("National Historical Park", .historicSite),
            ("National Historical Park and Preserve", .historicSite),
            ("International Historic Site", .historicSite),
            ("Part of Colonial National Historical Park", .historicSite),
            ("National Battlefield", .battlefield),
            ("National Military Park", .battlefield),
            ("National Battlefield Park", .battlefield),
            ("National Memorial", .memorial),
            ("Memorial", .memorial),
            ("Memorial Parkway", .parkway),
            ("Parkway", .parkway),
            ("National Seashore", .seashore),
            ("National Lakeshore", .seashore),
            ("National Recreation Area", .recreationArea),
            ("National River & Recreation Area", .river),
            ("Wild & Scenic River", .river),
            ("National Scenic Riverways", .river),
            ("National Preserve", .nationalPreserve),
            ("National Reserve", .nationalPreserve),
            ("Park", .otherNPSSite),
            ("National Park Service site", .otherNPSSite),
        ]
    )
    func npsDesignations(designation: String, expected: SiteType) {
        #expect(SiteType.classify(kind: .npsUnit, designation: designation) == expected)
    }

    @Test("other kinds take their type from the kind")
    func otherKinds() {
        #expect(SiteType.classify(kind: .nationalPark, designation: "National Park and Preserve")
            == .nationalPark)
        #expect(SiteType.classify(kind: .nationalForest, designation: "National Forest")
            == .nationalForest)
        #expect(SiteType.classify(kind: .blmMonument, designation: "National Volcanic Monument")
            == .nationalMonument)
        #expect(SiteType.classify(kind: .blmMonument, designation: "Outstanding Natural Area")
            == .conservationArea)
        #expect(SiteType.classify(kind: .scenicByway, designation: "All-American Road")
            == .scenicByway)
    }

    @Test("every type belongs to exactly one group, and every group has types")
    func groups() {
        let grouped = SiteType.Group.allCases.flatMap(\.types)
        #expect(grouped.count == SiteType.allCases.count)
        #expect(Set(grouped) == Set(SiteType.allCases))
        for group in SiteType.Group.allCases {
            #expect(!group.types.isEmpty)
        }
    }

    @Test("a type's key tier matches the tier of the kinds that produce it")
    func tiers() {
        // BLM and Forest Service monuments share the NPS's monument type but keep their own
        // tier's shape on the map; that is the one deliberate exception.
        for kind in PlaceKind.allCases where kind != .blmMonument {
            let type = SiteType.classify(kind: kind, designation: "National Monument")
            #expect(type.tier == kind.tier, "\(kind) gave \(type)")
        }
    }

    @Test("a factual description says only what the fields say")
    func factualDescription() {
        let forest = Place(
            id: "nf-white-river", name: "White River", designation: "National Forest",
            kind: .nationalForest, states: [USState.named("CO")].compactMap(\.self),
            centre: Coordinate(latitude: 39.5, longitude: -107)
        )
        #expect(forest.factualDescription
            == "A national forest in Colorado, managed by the US Forest Service.")

        let refuge = Place(
            id: "nwr-x", name: "X", designation: "National Wildlife Refuge",
            kind: .wildlifeRefuge,
            states: ["ND", "SD", "MN"].compactMap(USState.named),
            centre: Coordinate(latitude: 46, longitude: -97)
        )
        #expect(refuge.factualDescription.hasPrefix(
            "A wildlife refuge in North Dakota, South Dakota and Minnesota"
        ))

        let byway = Place(
            id: "byway-x", name: "X", designation: "All-American Road", kind: .scenicByway,
            agency: .other, states: [], centre: Coordinate(latitude: 0, longitude: 0)
        )
        #expect(byway.factualDescription
            == "An All-American Road, designated by the US Department of Transportation.")
    }
}

@Suite("Routes")
struct RouteGeometryTests {
    private let line = [
        Coordinate(latitude: 40, longitude: -100),
        Coordinate(latitude: 40, longitude: -99),
    ]

    @Test("a point on the line is no distance from it")
    func onTheLine() {
        let midway = Coordinate(latitude: 40, longitude: -99.5)
        #expect(RouteGeometry.distance(from: midway, to: line) < 1)
    }

    @Test("a point off the line is its perpendicular distance away")
    func offTheLine() {
        let north = Coordinate(latitude: 40.01, longitude: -99.5)
        let distance = RouteGeometry.distance(from: north, to: line)
        // A hundredth of a degree of latitude is about 1,113 metres.
        #expect(abs(distance - 1113) < 10)
    }

    @Test("beyond the end, the distance is to the end point")
    func pastTheEnd() {
        let east = Coordinate(latitude: 40, longitude: -98.9)
        let distance = RouteGeometry.distance(from: east, to: line)
        // Flat-earth against haversine: within half a percent over a few kilometres.
        #expect(abs(distance - line[1].distance(to: east)) < line[1].distance(to: east) * 0.005)
    }

    @Test("the midpoint is halfway along")
    func midpoint() throws {
        let route = RouteLine(name: "x", paths: [line])
        let middle = try #require(route.midpoint)
        #expect(abs(middle.longitude + 99.5) < 0.001)
        #expect(abs(route.length - 85200) < 600)
    }

    @Test("a route round-trips through its encoded form")
    func codable() throws {
        let route = RouteLine(name: "US 50", paths: [line])
        let data = try JSONEncoder().encode(route)
        let again = try JSONDecoder().decode(RouteLine.self, from: data)
        #expect(again.name == "US 50")
        #expect(again.paths == route.paths)
    }

    @Test("Amtrak routes near a point are found, and far ones are not")
    func nearbyRoutes() {
        let network = TransportNetwork(
            amtrakRoutes: [RouteLine(name: "Near", paths: [line])],
            amtrakStations: [
                RailStation(
                    code: "AAA",
                    name: "A",
                    location: Coordinate(latitude: 40, longitude: -99.6)
                ),
                RailStation(
                    code: "BBB",
                    name: "B",
                    location: Coordinate(latitude: 45, longitude: -90)
                ),
            ]
        )
        let point = Coordinate(latitude: 40.05, longitude: -99.5)
        #expect(network.amtrakRoutes(near: point, within: 10000).map(\.name) == ["Near"])
        #expect(network.amtrakRoutes(near: point, within: 1000).isEmpty)
        #expect(network.nearestStation(to: point)?.station.code == "AAA")
    }

    @Test("train access measures to the outline and names the services")
    func trainAccess() throws {
        let square = BoundaryPolygon(exterior: [
            Coordinate(latitude: 40, longitude: -100),
            Coordinate(latitude: 40, longitude: -99.9),
            Coordinate(latitude: 40.1, longitude: -99.9),
            Coordinate(latitude: 40.1, longitude: -100),
        ])
        let boundary = PlaceBoundary(polygons: [square])
        let place = Place(
            id: "p", name: "P", designation: "", kind: .nationalPark, states: [],
            centre: Coordinate(latitude: 40.05, longitude: -99.95)
        )
        let station = RailStation(
            code: "STN", name: "Station", location: Coordinate(latitude: 39.99, longitude: -99.95)
        )
        let line = [
            Coordinate(latitude: 39.99, longitude: -101),
            Coordinate(latitude: 39.99, longitude: -99),
        ]
        let network = TransportNetwork(
            amtrakRoutes: [RouteLine(name: "Line", paths: [line])],
            amtrakStations: [station]
        )
        let access = try #require(network.trainAccess(to: place, boundary: boundary))
        #expect(access.station.code == "STN")
        // A hundredth of a degree south of the outline: about 1.1 km, not the 6.7 km to
        // the centre.
        #expect(abs(access.metres - 1113) < 20)
        #expect(access.measuredToBoundary)
        #expect(access.services == ["Line"])
        #expect(network.trainAccess(to: place, boundary: boundary, within: 500) == nil)
    }
}

@Suite("Summary credits")
struct SummaryCreditTests {
    private func place(_ source: String?, url: String? = nil) -> Place {
        Place(
            id: "sp-co-golden-gate-canyon",
            name: "Golden Gate Canyon",
            designation: "State Park",
            kind: .statePark,
            states: [],
            centre: Coordinate(latitude: 39.8, longitude: -105.4),
            summary: "A state park in Colorado.",
            summarySource: source,
            summaryURL: url.flatMap(URL.init(string:)),
            summaryLicence: source == "Wikipedia" ? "CC BY-SA 4.0" : nil
        )
    }

    @Test("a Wikipedia lead is credited by article and licence, and as adapted")
    func wikipedia() {
        let credit = place(
            "Wikipedia", url: "https://en.wikipedia.org/wiki/Golden_Gate_Canyon_State_Park"
        ).summaryCredit
        #expect(
            credit == "Adapted from the Wikipedia article \u{201C}Golden Gate Canyon State "
                + "Park\u{201D}, CC BY-SA 4.0"
        )
    }

    @Test("agency prose names the agency, and prose written for the app needs no line")
    func others() {
        #expect(place("National Park Service").summaryCredit == "From the National Park Service")
        #expect(place("Unigrids").summaryCredit == nil)
        #expect(place(nil).summaryCredit == nil)
    }
}
