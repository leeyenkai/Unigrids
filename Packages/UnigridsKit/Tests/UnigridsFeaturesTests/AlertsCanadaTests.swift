import Foundation
import Testing
@testable import UnigridsFeatures

@Suite("Environment Canada's alerts and Avalanche Canada's forecasts")
struct AlertsCanadaTests {
    /// The shape MSC GeoMet's `weather-alerts` collection answers in, trimmed.
    private let alerts = Data(#"""
    {"type":"FeatureCollection","features":[
     {"type":"Feature","properties":{"alert_code":"SPS","alert_type":"statement",
      "alert_name_en":"special weather statement","alert_text_en":"Snow this evening.",
      "risk_colour_en":null,"feature_name_en":"Banff National Park","feature_id":"a",
      "status_en":"continued","expiration_datetime":"2026-11-18T02:51:35.439Z"}},
     {"type":"Feature","properties":{"alert_code":"SNW","alert_type":"warning",
      "alert_name_en":"snowfall warning","alert_text_en":"25 cm of snow.",
      "risk_colour_en":"yellow","feature_name_en":"Banff National Park","feature_id":"a",
      "status_en":"issued","expiration_datetime":"2026-11-18T12:00:00Z"}},
     {"type":"Feature","properties":{"alert_code":"SNW","alert_type":"warning",
      "alert_name_en":"snowfall warning","alert_text_en":"25 cm of snow.",
      "risk_colour_en":"yellow","feature_name_en":"Banff National Park","feature_id":"b",
      "status_en":"issued","expiration_datetime":"2026-11-18T12:00:00Z"}},
     {"type":"Feature","properties":{"alert_code":"WND","alert_type":"warning",
      "alert_name_en":"wind warning","risk_colour_en":"orange",
      "feature_name_en":"Kananaskis","feature_id":"c","status_en":"issued",
      "expiration_datetime":"2026-11-18T12:00:00Z"}},
     {"type":"Feature","properties":{"alert_code":"FRW","alert_type":"warning",
      "alert_name_en":"freezing rain warning","risk_colour_en":"yellow",
      "feature_name_en":"Canmore","feature_id":"d","status_en":"ended",
      "expiration_datetime":"2026-11-18T12:00:00Z"}},
     {"type":"Feature","properties":{}}
    ]}
    """#.utf8)

    private let now = Date(timeIntervalSince1970: 1_794_960_000) // 2026-11-18T00:00Z

    @Test("ended alerts are dropped, one alert over two areas shows once, colour sets kind")
    func weatherAlerts() throws {
        let parsed = try ECCCAlerts.alerts(from: alerts, now: now)
        #expect(parsed.map(\.title) == [
            "Special weather statement: Banff National Park",
            "Snowfall warning: Banff National Park",
            "Wind warning: Kananaskis",
        ])
        #expect(parsed.map(\.kind) == [.information, .caution, .danger])
        #expect(parsed.allSatisfy { $0.source == .eccc })
    }

    @Test("an alert past its expiry is none")
    func expired() throws {
        let later = now.addingTimeInterval(6 * 3600)
        let parsed = try ECCCAlerts.alerts(from: alerts, now: later)
        #expect(!parsed.contains { $0.title.hasPrefix("Special weather") })
    }

    private func product(_ ratings: [String], id: String = "r1") -> Data {
        let bands = zip(["alp", "tln", "btl"], ratings).map { band, value in
            #""\#(band)":{"display":"x","rating":{"value":"\#(value)","display":"x"}}"#
        }
        return Data(#"""
        {"url":"https://avalanche.ca/forecasts/r1","report":{"id":"\#(id)",
         "title":"Banff, Yoho and Kootenay","highlights":"<h1>Watch for <b>wind slabs</b>.</h1>",
         "dangerRatings":[{"date":{"value":"2026-11-18"},
          "ratings":{\#(bands.joined(separator: ","))}}]}}
        """#.utf8)
    }

    @Test("the highest band sets the level on the North American scale")
    func avalanche() throws {
        let considerable = try JSONDecoder().decode(
            AvalancheCanada.Product.self, from: product(["considerable", "moderate", "low"])
        )
        let alert = try #require(AvalancheCanada.alert(for: considerable))
        #expect(alert.title == "Avalanche danger 3, considerable, in Banff, Yoho and Kootenay")
        #expect(alert.kind == .caution)
        #expect(alert.description == "Watch for wind slabs.")
        let high = try JSONDecoder().decode(
            AvalancheCanada.Product.self, from: product(["high", "considerable", "moderate"])
        )
        #expect(AvalancheCanada.alert(for: high)?.kind == .danger)
    }

    @Test("early season, no rating and a point outside every region make no alert")
    func noRating() throws {
        let early = try JSONDecoder().decode(
            AvalancheCanada.Product.self, from: product(["earlyseason", "earlyseason", "norating"])
        )
        #expect(AvalancheCanada.alert(for: early) == nil)
        let outside = try JSONDecoder().decode(
            AvalancheCanada.Product.self, from: product(["low", "low", "low"], id: "")
        )
        #expect(AvalancheCanada.alert(for: outside) == nil)
    }
}
