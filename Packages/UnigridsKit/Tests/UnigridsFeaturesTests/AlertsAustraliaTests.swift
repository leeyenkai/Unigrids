import Foundation
import Testing
import UnigridsCore
@testable import UnigridsFeatures

@Suite("Australia's fire and park alerts")
struct AlertsAustraliaTests {
    private let blueMountains = Place(
        id: "au-np-blue-mountains", name: "Blue Mountains", designation: "National Park",
        kind: .nationalPark, states: [], centre: Coordinate(latitude: -33.7, longitude: 150.3),
        country: .australia, subdivisions: [Subdivision(code: "AU-NSW", name: "New South Wales")]
    )

    /// A square park from 33.6° to 33.8° south, 150.2° to 150.4° east.
    private let boundary = PlaceBoundary(polygons: [
        BoundaryPolygon(exterior: [
            Coordinate(latitude: -33.6, longitude: 150.2),
            Coordinate(latitude: -33.6, longitude: 150.4),
            Coordinate(latitude: -33.8, longitude: 150.4),
            Coordinate(latitude: -33.8, longitude: 150.2),
        ]),
    ])

    @Test("NSW RFS: the level reads from the category, the point from inside a collection")
    func rfs() throws {
        let data = Data(#"""
        {"type":"FeatureCollection","features":[
         {"type":"Feature","geometry":{"type":"GeometryCollection","geometries":[
           {"type":"Point","coordinates":[150.3,-33.7]},
           {"type":"Polygon","coordinates":[[[150.2,-33.6],[150.3,-33.6],[150.3,-33.7]]]}]},
          "properties":{"title":"MOUNT HAY RD, LEURA","link":"https://www.rfs.nsw.gov.au/x",
           "category":"Watch and Act","guid":"https://incidents.rfs.nsw.gov.au/1",
           "description":"ALERT LEVEL: Watch and Act <br />LOCATION: Leura"}},
         {"type":"Feature","geometry":{"type":"Point","coordinates":[151.0,-30.0]},
          "properties":{"title":"FAR AWAY","category":"Not Applicable","guid":"2",
           "description":"ALERT LEVEL: Not Applicable"}}
        ]}
        """#.utf8)
        let incidents = try AustralianFires.incidents(from: data, feed: .nswRFS)
        #expect(incidents.count == 2)
        #expect(incidents[0].title == "Mount Hay Rd, Leura")
        #expect(incidents[0].location == Coordinate(latitude: -33.7, longitude: 150.3))
        #expect(AustralianFires.alert(for: incidents[0]).kind == .caution)
        #expect(incidents[1].level == nil)
        #expect(AustralianFires.alert(for: incidents[1]).kind == .information)
        #expect(AustralianFires.touches(incidents[0], place: blueMountains, boundary: boundary))
        #expect(!AustralianFires.touches(incidents[1], place: blueMountains, boundary: boundary))
    }

    @Test("a fire just over the boundary is the park's; one well beyond is not")
    func nearTheEdge() {
        func fire(_ latitude: Double, _ longitude: Double) -> FireIncident {
            FireIncident(
                id: "x", title: "x", detail: "", level: "Advice",
                location: Coordinate(latitude: latitude, longitude: longitude), url: ""
            )
        }
        #expect(AustralianFires.touches(
            fire(-33.62, 150.41),
            place: blueMountains,
            boundary: boundary
        ))
        #expect(!AustralianFires.touches(
            fire(-33.7, 150.6),
            place: blueMountains,
            boundary: boundary
        ))
    }

    @Test("Queensland's and Western Australia's warnings carry their levels")
    func otherStates() throws {
        let qld = Data(#"""
        {"type":"FeatureCollection","features":[{"type":"Feature",
         "geometry":{"type":"Polygon","coordinates":[[[139.3,-20.4],[139.4,-20.4],[139.4,-20.5]]]},
         "properties":{"UniqueID":"WARN-1","WarningTitle":"PREPARE TO LEAVE - Lawn Hill",
          "WarningLevel":"Emergency Warning","Header":"A fire is burning.",
          "Latitude":"-18.7","Longitude":"138.5"}}]}
        """#.utf8)
        let warning = try #require(try AustralianFires.incidents(from: qld, feed: .qldFire).first)
        #expect(warning.location == Coordinate(latitude: -18.7, longitude: 138.5))
        #expect(AustralianFires.alert(for: warning).kind == .danger)

        let wa = Data(#"""
        {"warnings":[{"id":"w1","warning-type":"Bushfire Watch and Act",
          "title":"WATCH AND ACT - KARIJINI NATIONAL PARK","alert-line":"<p>A bushfire.</p>",
          "location":{"latitude":-22.6,"longitude":118.3,"value":"Karijini"}}]}
        """#.utf8)
        let dfes = try #require(try AustralianFires.incidents(from: wa, feed: .waDFES).first)
        #expect(dfes.level == "Watch and Act")
        #expect(dfes.detail == "A bushfire.")
    }

    @Test("an NPWS item splits into its notices, each with its kind")
    func npws() throws {
        let rss = Data(#"""
        <?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel>
        <item><title>Blue Mountains National Park</title>
        <link>https://www.nationalparks.nsw.gov.au/bm/local-alerts</link>
        <description>&lt;strong&gt;Closed areas: Parts of Blue Mountains National Park
        closed&lt;/strong&gt;
        &lt;br/&gt;Tracks are closed.&lt;strong&gt;Katoomba &lt;/strong&gt;
        &lt;ul&gt;&lt;li&gt;Furber Steps closed.&lt;/li&gt;&lt;/ul&gt;
        &lt;strong&gt;Fire bans: Park Fire Ban&lt;/strong&gt;No fires.</description>
        </item>
        <item><title>Royal National Park</title><link>x</link><description></description></item>
        </channel></rss>
        """#.utf8)
        let items = NPWSAlerts.items(from: rss)
        let item = try #require(NPWSAlerts.item(for: blueMountains, in: items))
        #expect(item.notices.map(\.heading) == ["Closed areas", "Fire bans"])
        #expect(item.notices[0].body.contains("Furber Steps closed."))
        let alerts = item.notices.map { NPWSAlerts.alert(for: $0, of: item) }
        #expect(alerts.map(\.kind) == [.closure, .caution])
        #expect(alerts[0].title == "Parts of Blue Mountains National Park closed")
    }

    @MainActor
    @Test("a park in a state with no readable feed is not covered")
    func coverage() {
        let flinders = Place(
            id: "au-np-ikara-flinders-ranges", name: "Ikara-Flinders Ranges",
            designation: "National Park", kind: .nationalPark, states: [],
            centre: Coordinate(latitude: -31.5, longitude: 138.6), country: .australia,
            subdivisions: [Subdivision(code: "AU-SA", name: "South Australia")]
        )
        #expect(!AlertsCenter.covers(flinders))
        #expect(AlertsCenter.covers(blueMountains))
    }
}
