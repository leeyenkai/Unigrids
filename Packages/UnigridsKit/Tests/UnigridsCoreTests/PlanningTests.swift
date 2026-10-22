import Foundation
import Testing
@testable import UnigridsCore

@Suite("Trails")
struct TrailRuleTests {
    @Test(
        "difficulty follows Shenandoah's published bands",
        arguments: [
            // (metres, gain metres, expected)
            (1609.344, 0.0, TrailDifficulty.easy),
            // 1 mile, 1000 ft: sqrt(2000) ≈ 44.7
            (1609.344, 304.8, .easy),
            // 4 miles, 1000 ft: sqrt(8000) ≈ 89.4
            (6437.376, 304.8, .moderate),
            // 8 miles, 1000 ft: sqrt(16000) ≈ 126.5
            (12874.752, 304.8, .moderatelyStrenuous),
            // 8 miles, 2000 ft: sqrt(32000) ≈ 178.9
            (12874.752, 609.6, .strenuous),
            // 16 miles, 4800 ft: sqrt(153600) ≈ 391.9
            (25749.504, 1463.04, .veryStrenuous),
        ]
    )
    func difficultyBands(length: Double, gain: Double, expected: TrailDifficulty) {
        #expect(TrailDifficulty.estimate(lengthMetres: length, gainMetres: gain) == expected)
    }

    @Test("an unmeasured trail has no estimated difficulty, and climbs nothing")
    func unmeasured() {
        let trail = Trail(id: "t", placeID: "p", name: "T", lengthMetres: 5000)
        #expect(trail.estimatedDifficulty == nil)
        #expect(!trail.isMeasured)
        // Ten kilometres there and back at 5 km/h.
        #expect(trail.estimatedDuration == 7200)
    }

    @Test("a trail mapped one way is hiked there and back; a loop once round")
    func roundTrips() {
        // Bright Angel, near enough: mapped rim to river, so it barely rises one way.
        let canyon = Trail(
            id: "t", placeID: "p", name: "T", lengthMetres: 12700, gainMetres: 30, lossMetres: 1340
        )
        #expect(canyon.walkedMetres == 25400)
        #expect(canyon.climbMetres == 1370)
        #expect(canyon.estimatedDifficulty == .veryStrenuous)
        let loop = Trail(
            id: "l", placeID: "p", name: "L", lengthMetres: 5000, gainMetres: 200, lossMetres: 200,
            routeType: .loop
        )
        #expect(loop.walkedMetres == 5000)
        #expect(loop.climbMetres == 200)
    }

    @Test("a trail round-trips through the bundle's compact form")
    func codable() throws {
        let path = [
            Coordinate(latitude: 1, longitude: 2),
            Coordinate(latitude: 1.001, longitude: 2),
        ]
        let trail = Trail(
            id: "t", placeID: "p", name: "T", lengthMetres: 1200, gainMetres: 80,
            routeType: .loop, features: [.lake],
            paths: [path],
            profile: [TrailProfilePoint(distanceMetres: 0, elevationMetres: 1500)]
        )
        let again = try JSONDecoder().decode(Trail.self, from: JSONEncoder().encode(trail))
        #expect(again == trail)
    }

    @Test("a dataset feature the app does not know is dropped, not fatal")
    func unknownFeature() throws {
        let json = #"{"id":"t","placeID":"p","name":"T","lengthMetres":10,"#
            + #""features":["lake","volcano"]}"#
        let trail = try JSONDecoder().decode(Trail.self, from: Data(json.utf8))
        #expect(trail.features == [.lake])
    }
}

@Suite("Trail filters")
struct TrailFilterTests {
    private let easyLoop = Trail(
        id: "a", placeID: "p", name: "Lake Loop", lengthMetres: 3000, gainMetres: 20,
        routeType: .loop, features: [.lake]
    )
    private let longClimb = Trail(
        id: "b", placeID: "p", name: "Summit Trail", lengthMetres: 9000, gainMetres: 1500,
        features: [.summit]
    )
    private let unmeasured = Trail(id: "c", placeID: "p", name: "Creek Path", lengthMetres: 7000)

    @Test("an empty filter lets everything through")
    func everything() {
        let filter = TrailFilter()
        #expect(!filter.isNarrowed)
        for trail in [easyLoop, longClimb, unmeasured] {
            #expect(filter.includes(trail, hiked: false))
        }
    }

    @Test("length, effort, loops, features and the log narrow")
    func narrowing() {
        #expect(TrailFilter(length: .short).includes(easyLoop, hiked: false))
        #expect(!TrailFilter(length: .short).includes(longClimb, hiked: false))
        #expect(TrailFilter(difficulties: [.veryStrenuous]).includes(longClimb, hiked: false))
        // An unmeasured trail has no effort band to match.
        #expect(!TrailFilter(difficulties: [.easy]).includes(unmeasured, hiked: false))
        #expect(!TrailFilter(loopsOnly: true).includes(longClimb, hiked: false))
        #expect(TrailFilter(features: [.lake, .glacier]).includes(easyLoop, hiked: false))
        #expect(!TrailFilter(notYetHiked: true).includes(easyLoop, hiked: true))
        #expect(TrailFilter(query: "summit").includes(longClimb, hiked: false))
    }

    @Test("sorting puts unmeasured trails last on climb")
    func sorting() {
        let byClimb = TrailFilter.sorted([unmeasured, easyLoop, longClimb], by: .climb)
        #expect(byClimb.map(\.id) == ["b", "a", "c"])
        let byEffort = TrailFilter.sorted([longClimb, unmeasured, easyLoop], by: .effort)
        #expect(byEffort.map(\.id) == ["a", "b", "c"])
        #expect(TrailFilter.sorted([easyLoop, longClimb], by: .length).first?.id == "b")
    }
}

@Suite("Trip schedule")
struct TripScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: value, hour: 9)) ?? Date()
    }

    @Test("legs count toward the day they arrive on, and a long day is flagged")
    func days() {
        let stops: [(id: UnigridsID, date: Date?)] = [
            ("a", day(1)), ("b", day(1)), ("c", day(2)), ("d", nil),
        ]
        let legs = [
            DriveLeg(from: "a", to: "b", seconds: 2 * 3600, metres: 150_000),
            DriveLeg(from: "b", to: "c", seconds: 7 * 3600, metres: 600_000),
            DriveLeg(from: "c", to: "d", seconds: 3600, metres: 80000),
        ]
        let plan = TripSchedule.days(stops: stops, legs: legs, calendar: calendar)
        #expect(plan.count == 2)
        #expect(plan[0].stopIDs == ["a", "b"])
        #expect(plan[0].drivingSeconds == 2 * 3600)
        #expect(!plan[0].isLong)
        #expect(plan[1].drivingSeconds == 7 * 3600)
        #expect(plan[1].isLong)
    }

    @Test("closure season is November to April")
    func closureSeason() {
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)) ?? Date()
        let july = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)) ?? Date()
        #expect(TripSchedule.isClosureSeason(january, calendar: calendar))
        #expect(!TripSchedule.isClosureSeason(july, calendar: calendar))
    }
}

@Suite("Weather")
struct WeatherTests {
    @Test("WMO codes fall into conditions")
    func codes() {
        #expect(WeatherCondition(code: 0) == .clear)
        #expect(WeatherCondition(code: 63) == .rain)
        #expect(WeatherCondition(code: 75) == .snow)
        #expect(WeatherCondition(code: 96) == .thunderstorm)
        #expect(WeatherCondition(code: 63).isWet)
        #expect(!WeatherCondition(code: 2).isWet)
    }

    @Test("an Open-Meteo daily response decodes, nulls and all")
    func decoding() throws {
        let json = #"""
        {"daily":{"time":["2026-07-01","2026-07-02"],"weather_code":[0,null],
        "temperature_2m_max":[31.5,29.0],"temperature_2m_min":[15.2,null],
        "precipitation_probability_max":[5,60],"sunrise":["2026-07-01T05:58","2026-07-02T05:59"],
        "sunset":["2026-07-01T20:41","2026-07-02T20:41"]}}
        """#
        let decoded = try JSONDecoder().decode(OpenMeteoDaily.self, from: Data(json.utf8))
        #expect(decoded.days.count == 2)
        let first = try #require(decoded.day("2026-07-01"))
        #expect(first.condition == .clear)
        #expect(first.highCelsius == 31.5)
        #expect(decoded.days[1].code == nil)
        #expect(decoded.days[1].precipitationProbability == 60)
    }
}

@Suite("GPX")
struct GPXTests {
    @Test("waypoints and a route, escaped")
    func document() {
        let gpx = TripGPX.document(name: "Utah & Arizona", waypoints: [
            .init(name: "Zion", coordinate: Coordinate(latitude: 37.29, longitude: -113.03)),
            .init(
                name: "Bryce <Canyon>",
                coordinate: Coordinate(latitude: 37.57, longitude: -112.18)
            ),
        ])
        #expect(gpx.contains("<name>Utah &amp; Arizona</name>"))
        #expect(gpx.contains(#"<wpt lat="37.29000" lon="-113.03000">"#))
        #expect(gpx.contains("Bryce &lt;Canyon&gt;"))
        #expect(gpx.contains("<rte>"))
        #expect(gpx.hasSuffix("</gpx>\n"))
    }
}

@Suite("Photo import")
struct PhotoImportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 6, day: day, hour: hour)) ?? Date()
    }

    private let locator: PlaceLocator = {
        func square(_ lat: Double, _ lon: Double, _ size: Double) -> PlaceBoundary {
            let ring = [
                Coordinate(latitude: lat, longitude: lon),
                Coordinate(latitude: lat, longitude: lon + size),
                Coordinate(latitude: lat + size, longitude: lon + size),
                Coordinate(latitude: lat + size, longitude: lon),
            ]
            return PlaceBoundary(polygons: [BoundaryPolygon(exterior: ring)])
        }
        return PlaceLocator(boundaries: [
            "forest": square(37, -114, 2),
            "park": square(37.2, -113.2, 0.3),
        ])
    }()

    @Test("a point finds the smallest outline that holds it")
    func locate() {
        #expect(locator.place(at: Coordinate(latitude: 37.3, longitude: -113.1)) == "park")
        #expect(locator.place(at: Coordinate(latitude: 38.5, longitude: -113.9)) == "forest")
        #expect(locator.place(at: Coordinate(latitude: 30, longitude: -100)) == nil)
    }

    @Test("photos become one visit per place per day, skipping days already logged")
    func propose() {
        let inPark = Coordinate(latitude: 37.3, longitude: -113.1)
        let photos = [
            GeoPhoto(id: "a", date: at(1, 9), location: inPark),
            GeoPhoto(id: "b", date: at(1, 15), location: inPark),
            GeoPhoto(id: "c", date: at(2, 10), location: inPark),
            GeoPhoto(id: "d", date: at(9, 10), location: inPark),
            GeoPhoto(id: "x", date: at(1, 10), location: Coordinate(latitude: 0, longitude: 0)),
        ]
        let loggedDay = calendar.startOfDay(for: at(2, 0))
        let logged: Set<String> = [PhotoVisits.loggedKey("park", loggedDay)]
        let visits = PhotoVisits.propose(
            photos: photos, locator: locator, alreadyLogged: logged, calendar: calendar
        )
        #expect(visits.count == 2)
        #expect(visits[0].photoIDs == ["a", "b"])
        #expect(visits[1].photoIDs == ["d"])

        let trips = PhotoVisits.trips(from: visits, calendar: calendar)
        #expect(trips.count == 2)
    }
}

@Suite("Weather stats")
struct WeatherStatsTests {
    private func visit(
        _ high: Double?,
        _ low: Double?,
        _ rain: Double?,
        _ condition: WeatherCondition?
    ) -> VisitWeather {
        VisitWeather(
            placeID: "p", date: Date(), highCelsius: high, lowCelsius: low,
            precipitationMillimetres: rain, condition: condition?.name
        )
    }

    @Test("hottest, coldest, wettest and snow days")
    func extremes() {
        let stats = WeatherStats([
            visit(38, 22, 0, .clear),
            visit(-2, -12, 6, .snow),
            visit(15, 5, 22, .rain),
            visit(nil, nil, nil, nil),
        ])
        #expect(stats.measured == 3)
        #expect(stats.hottest?.highCelsius == 38)
        #expect(stats.coldest?.lowCelsius == -12)
        #expect(stats.wettest?.precipitationMillimetres == 22)
        #expect(stats.snowVisits == 1)
        #expect(stats.wetVisits == 2)
        #expect(stats.verdict == nil)
    }

    @Test("the verdict needs five visits, then reads the share of wet ones")
    func verdict() {
        let dry = Array(repeating: visit(20, 10, 0, .clear), count: 9)
        #expect(WeatherStats(dry + [visit(10, 5, 5, .rain)]).verdict == .fairWeather)
        let wet = Array(repeating: visit(10, 5, 8, .rain), count: 3)
        #expect(WeatherStats(wet + Array(dry.prefix(3))).verdict == .stormChaser)
        #expect(WeatherStats(Array(wet.prefix(2)) + Array(dry.prefix(4))).verdict == .allWeather)
    }

    @Test("visits by month count each month once per visit")
    func byMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let dates = [1, 1, 7].compactMap {
            calendar.date(from: DateComponents(year: 2025, month: $0, day: 15))
        }
        let counts = StatsReport.visitsByMonth(
            dates.map { VisitSummary(placeID: "p", date: $0) }, calendar: calendar
        )
        #expect(counts[0] == 2)
        #expect(counts[6] == 1)
        #expect(counts.reduce(0, +) == 3)
    }
}
