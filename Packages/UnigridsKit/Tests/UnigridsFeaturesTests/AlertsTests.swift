import Foundation
import Testing
import UnigridsCore
@testable import UnigridsFeatures

@Suite("Live alerts")
struct AlertsTests {
    @Test("one malformed alert costs that alert, not the page")
    func lossyDecoding() throws {
        let json = Data(#"""
        {"total": "3", "data": [
          {"id": "a", "title": "Road closed", "description": "Snow.", "category": "Park Closure",
           "url": "", "parkCode": "zion"},
          {"id": "b", "title": null, "description": "Broken.", "category": "Danger"},
          {"id": "c", "title": "Flash floods", "description": "Narrows closed.",
           "category": "Danger", "url": "https://www.nps.gov/zion", "parkCode": "zion"}
        ]}
        """#.utf8)
        let response = try JSONDecoder().decode(NPSAlerts.Response.self, from: json)
        #expect(response.data.map(\.id) == ["a", "c"])
        #expect(response.total == 3)
        #expect(response.data.first?.kind == .closure)
        #expect(response.data.allSatisfy { $0.source == .nps })
    }

    @Test("alerts are asked for by place, and a place no service covers has none")
    @MainActor
    func placeWithoutAService() {
        // A quasi-national park: Japan's warnings are offered for national parks only.
        let place = Place(
            id: "jp-qnp-ontakesan", name: "Ontakesan", designation: "Quasi-National Park",
            kind: .quasiNationalPark, states: [],
            centre: Coordinate(latitude: 35.89, longitude: 137.48), country: .japan
        )
        #expect(!AlertsCenter.covers(place))
        #expect(AlertsCenter().alerts(for: place).isEmpty)
        #expect(AlertsCenter().mapLevel(for: place) == nil)
    }

    @Test("pages continue while they come back full, total or no total")
    func paging() {
        let size = NPSAlerts.pageSize
        #expect(NPSAlerts.morePages(received: size, start: size, total: nil))
        #expect(!NPSAlerts.morePages(received: size - 1, start: size, total: nil))
        #expect(!NPSAlerts.morePages(received: size, start: size, total: size))
        #expect(NPSAlerts.morePages(received: size, start: size, total: size * 2 + 1))
    }
}

@Suite("Warnings abroad")
struct AlertsAbroadTests {
    @Test("a feed whose entries all fail to decode is an error, not an all-clear")
    func changedShape() throws {
        let renamed = Data(#"[{"RegionId": 3011, "RegionName": "Tromsø", "DangerLevel": 3}]"#.utf8)
        #expect(throws: DecodingError.self) {
            try lossyValues(JSONDecoder().decode(
                [Lossy<VarsomAvalanche.Forecast>].self, from: renamed
            ))
        }
        let empty = try lossyValues(JSONDecoder().decode(
            [Lossy<VarsomAvalanche.Forecast>].self, from: Data("[]".utf8)
        ))
        #expect(empty.isEmpty)
    }

    @Test("Varsom is asked for Norway's date, not UTC's")
    func varsomDay() throws {
        // 23:30 UTC on 14 January is 00:30 on the 15th in Oslo.
        let moment = try #require(ISO8601DateFormatter().date(from: "2027-01-14T23:30:00Z"))
        #expect(VarsomAvalanche.forecastDay(moment) == "2027-01-15")
    }

    @Test("a cancelled request is not a failure")
    func cancellation() {
        #expect(isCancellation(CancellationError()))
        #expect(isCancellation(URLError(.cancelled)))
        #expect(!isCancellation(URLError(.timedOut)))
    }

    @Test("JMA's warnings are read per volcano, and levels in its own words")
    func jmaWarnings() throws {
        let json = Data(#"""
        [{"reportDatetime": "2021-03-08T14:00:00+09:00", "eventId": "508", "areas": ["4630300"],
          "volcanoInfos": [
            {"type": "噴火警報・予報（対象火山）", "items": [{"name": "レベル２（火口周辺規制）",
             "code": "12", "areas": [{"name": "薩摩硫黄島", "code": "508"}]}]},
            {"type": "噴火警報・予報（対象市町村等）", "items": [{"name": "火口周辺警報",
             "code": "02", "areas": [{"name": "鹿児島県三島村", "code": "4630300"}]}]}]},
         {"broken": true}]
        """#.utf8)
        let warnings = try JMAVolcanoes.warnings(from: json)
        #expect(warnings.count == 1)
        #expect(warnings.first?.volcanoCode == "508")
        #expect(JMAVolcanoes.level(of: "レベル２（火口周辺規制）")?.number == 2)
        #expect(JMAVolcanoes.level(of: "火口周辺危険") == nil)
        let volcano = JMAVolcanoes.Volcano(
            code: "508", nameEnglish: "Satsuma-Iojima", nameJapanese: "薩摩硫黄島",
            location: Coordinate(latitude: 30.79, longitude: 130.31)
        )
        let alert = try JMAVolcanoes.alert(for: #require(warnings.first), volcano: volcano)
        #expect(alert.kind == .closure && alert.source == .jma)
        #expect(alert.description.contains("レベル２"))
    }

    @Test("the volcano list keeps each volcano's place")
    func jmaVolcanoList() throws {
        let json = Data(#"""
        [{"code": "101", "latlon": ["44.133", "145.161"], "name_jp": "知床硫黄山",
          "name_en": "Shiretoko-Iozan"}, {"code": "x"}]
        """#.utf8)
        let volcanoes = try JMAVolcanoes.volcanoes(from: json)
        #expect(volcanoes.map(\.code) == ["101"])
        #expect(volcanoes.first?.location.latitude == 44.133)
    }

    @Test("Varsom's danger levels become alerts; no rating makes none")
    func varsomLevels() throws {
        let json = Data(#"""
        [{"RegionId": 3003, "RegionName": "Nordenskiöld Land", "DangerLevel": "3",
          "ValidFrom": "2026-03-02T00:00:00", "MainText": "Avoid avalanche terrain."},
         {"RegionId": 3028, "RegionName": "Jotunheimen", "DangerLevel": "0",
          "ValidFrom": "2026-11-16T00:00:00", "MainText": "No Rating"}]
        """#.utf8)
        let forecasts = try JSONDecoder().decode([VarsomAvalanche.Forecast].self, from: json)
        let alerts = forecasts.compactMap(VarsomAvalanche.alert(for:))
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .caution)
        #expect(alerts.first?.title.contains("Nordenskiöld Land") == true)
    }

    @Test("every national park abroad has a warning service; its source says whose")
    @MainActor
    func coverageAbroad() {
        let rondane = Place(
            id: "no-np-rondane", name: "Rondane", designation: "National Park",
            kind: .nationalPark, states: [], centre: Coordinate(latitude: 61.9, longitude: 9.8),
            country: .norway
        )
        #expect(AlertsCenter.covers(rondane))
        #expect(AlertsCenter.source(for: rondane) == .varsom)
    }
}

@Suite("Arrivals where people live")
@MainActor
struct ArrivalLimitTests {
    private func fresh() -> DetectedVisits {
        let suite = "arrivals-\(UUID().uuidString)"
        return DetectedVisits(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    @Test("a park with towns in it is suggested at most once a week")
    func weeklyGap() {
        let detected = fresh()
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let week: TimeInterval = 7 * 86400
        #expect(detected.add("jp-np-fuji-hakone-izu", at: monday, minimumGap: week))
        #expect(!detected.add("jp-np-fuji-hakone-izu", at: monday + 86400, minimumGap: week))
        #expect(detected.add("jp-np-fuji-hakone-izu", at: monday + week + 60, minimumGap: week))
    }

    @Test("a place the reader mutes is never suggested again, until they say so")
    func muting() throws {
        let detected = fresh()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(detected.add("jp-np-nikko", at: now))
        let suggestion = try #require(detected.pending.first)
        detected.mute(suggestion)
        #expect(detected.pending.isEmpty)
        #expect(!detected.add("jp-np-nikko", at: now + 3 * 86400))
        detected.clearMuted()
        #expect(detected.add("jp-np-nikko", at: now + 4 * 86400))
    }
}
