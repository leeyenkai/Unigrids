import Foundation
import Testing
@testable import UnigridsCore

@Suite("Encoded polylines")
struct PolylineTests {
    @Test("the format's published example decodes to its published points")
    func publishedExample() {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(abs(points[0].latitude - 38.5) < 1e-9)
        #expect(abs(points[0].longitude - -120.2) < 1e-9)
        #expect(abs(points[2].latitude - 43.252) < 1e-9)
        #expect(abs(points[2].longitude - -126.453) < 1e-9)
    }

    @Test("encoding and decoding round-trip at five decimal places")
    func roundTrip() {
        let points = [
            Coordinate(latitude: 37.12345, longitude: -112.98765),
            Coordinate(latitude: -14.25, longitude: -170.68),
            Coordinate(latitude: 63.0, longitude: 151.00001),
        ]
        let decoded = Polyline.decode(Polyline.encode(points))
        #expect(decoded.count == points.count)
        for (got, want) in zip(decoded, points) {
            #expect(abs(got.latitude - want.latitude) < 1e-5)
            #expect(abs(got.longitude - want.longitude) < 1e-5)
        }
    }

    @Test("a malformed string yields what decoded before the fault, not a crash")
    func malformed() {
        let valid = Polyline.encode([Coordinate(latitude: 1, longitude: 2)])
        #expect(Polyline.decode(valid + " ").count == 1)
        #expect(Polyline.decode("").isEmpty)
    }
}

@Suite("Place outlines")
struct PlaceBoundaryTests {
    private let square = [
        Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1),
        Coordinate(latitude: 1, longitude: 1), Coordinate(latitude: 1, longitude: 0),
    ]
    private let hole = [
        Coordinate(latitude: 0.25, longitude: 0.25), Coordinate(latitude: 0.25, longitude: 0.75),
        Coordinate(latitude: 0.75, longitude: 0.75), Coordinate(latitude: 0.75, longitude: 0.25),
    ]

    @Test("a point inside the exterior and outside any hole is inside")
    func containsRespectsHoles() {
        let polygon = BoundaryPolygon(exterior: square, holes: [hole])
        #expect(polygon.contains(Coordinate(latitude: 0.1, longitude: 0.1)))
        #expect(!polygon.contains(Coordinate(latitude: 0.5, longitude: 0.5)))
        #expect(!polygon.contains(Coordinate(latitude: 2, longitude: 2)))
    }

    @Test("winding does not matter")
    func winding() {
        let clockwise = BoundaryPolygon(exterior: square.reversed())
        #expect(clockwise.contains(Coordinate(latitude: 0.5, longitude: 0.5)))
    }

    @Test("an outline of several polygons contains a point in any of them")
    func multiPolygon() {
        let east = square.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude + 5) }
        let boundary = PlaceBoundary(polygons: [
            BoundaryPolygon(exterior: square), BoundaryPolygon(exterior: east),
        ])
        #expect(boundary.contains(Coordinate(latitude: 0.5, longitude: 5.5)))
        #expect(!boundary.contains(Coordinate(latitude: 0.5, longitude: 3)))
        #expect(boundary.extent == BoundingBox(south: 0, west: 0, north: 1, east: 6))
    }

    @Test("the bundled JSON shape decodes, and encodes back to the same outline")
    func codable() throws {
        let json = """
        {"bbox":[0,0,1,1],"polygons":[["\(Polyline.encode(square))","\(Polyline.encode(hole))"]]}
        """
        let boundary = try JSONDecoder().decode(PlaceBoundary.self, from: Data(json.utf8))
        #expect(boundary.polygons.count == 1)
        #expect(boundary.polygons[0].holes.count == 1)
        #expect(boundary.pointCount == 8)
        let again = try JSONDecoder().decode(
            PlaceBoundary.self, from: JSONEncoder().encode(boundary)
        )
        #expect(again == boundary)
    }
}

@Suite("Map filters")
struct MapFilterTests {
    private func place(_ kind: PlaceKind) -> Place {
        Place(
            id: "x", name: "X", designation: "", kind: kind, states: [],
            centre: Coordinate(latitude: 0, longitude: 0)
        )
    }

    @Test("everything lets everything through")
    func everything() {
        for kind in PlaceKind.allCases {
            #expect(MapFilter.everything.includes(place(kind), isVisited: false))
        }
        #expect(!MapFilter.everything.isNarrowed)
    }

    @Test("tiers and visits narrow together")
    func narrowing() {
        let filter = MapFilter(tiers: [.nationalPark], visits: .notVisited)
        #expect(filter.isNarrowed)
        #expect(filter.includes(place(.nationalPark), isVisited: false))
        #expect(!filter.includes(place(.nationalPark), isVisited: true))
        #expect(!filter.includes(place(.statePark), isVisited: false))
        #expect(MapFilter(visits: .visited).includes(place(.npsUnit), isVisited: true))
    }

    @Test("national parks are always outlined; the rest only at regional zoom")
    func outlineDetail() {
        #expect(MapDetail.showsOutline(for: .nationalPark, latitudeSpan: 60))
        #expect(!MapDetail.showsOutline(for: .statePark, latitudeSpan: 30))
        #expect(MapDetail.showsOutline(for: .statePark, latitudeSpan: 8))
    }

    @Test("park names print before the smaller sites' do")
    func labelDetail() {
        #expect(MapDetail.showsLabel(for: .nationalPark, latitudeSpan: 15))
        #expect(!MapDetail.showsLabel(for: .npsUnit, latitudeSpan: 15))
        #expect(MapDetail.showsLabel(for: .npsUnit, latitudeSpan: 2))
    }
}

@Suite("Trip planning")
struct TripPlanningTests {
    @Test("legs are measured stop to stop, in order")
    func legs() {
        let zion = Coordinate(latitude: 37.2, longitude: -112.98)
        let bryce = Coordinate(latitude: 37.6, longitude: -112.17)
        let legs = TripRoute.legDistances([zion, bryce, zion])
        #expect(legs.count == 2)
        // About 83 km as the crow flies.
        #expect((80000 ... 86000).contains(legs[0]))
        #expect(abs(TripRoute.totalDistance([zion, bryce, zion]) - 2 * legs[0]) < 1)
        #expect(TripRoute.totalDistance([zion]) == 0)
    }

    @Test("a trip exports as an iCalendar file with an all-day event per dated stop")
    func calendar() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let day = utc.date(from: DateComponents(year: 2027, month: 4, day: 15, hour: 9)) ?? Date()
        let text = TripCalendar.document(
            name: "Utah, in April",
            events: [
                TripCalendar.Event(title: "Zion National Park", day: day, notes: "Shuttle; early"),
            ],
            identifier: "trip-1",
            stamp: day,
            calendar: utc
        )
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(text.contains("DTSTART;VALUE=DATE:20270415\r\n"))
        #expect(text.contains("DTEND;VALUE=DATE:20270416\r\n"))
        #expect(text.contains("X-WR-CALNAME:Utah\\, in April"))
        #expect(text.contains("DESCRIPTION:Shuttle\\; early"))
        #expect(text.contains("UID:trip-1-0@unigrids"))
    }
}

@Suite("US tile grid")
struct USTileGridTests {
    @Test("every state, DC and the five territories has exactly one square")
    func complete() {
        let codes = USTileGrid.tiles.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(Set(codes) == Set(USState.all.map(\.code)))
    }

    @Test("no two squares share a cell, and all sit on the grid")
    func noOverlaps() {
        let cells = USTileGrid.tiles.map { "\($0.row),\($0.column)" }
        #expect(Set(cells).count == cells.count)
        for tile in USTileGrid.tiles {
            #expect((0 ..< USTileGrid.rows).contains(tile.row))
            #expect((0 ..< USTileGrid.columns).contains(tile.column))
        }
    }
}
