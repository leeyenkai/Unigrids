import Foundation
import Testing
@testable import UnigridsFeatures

@Suite("GeoNet volcanic alert levels")
struct AlertsSouthTests {
    private let sample = Data(#"""
    {"type":"FeatureCollection","features":[
     {"type":"Feature","geometry":{"type":"Point","coordinates":[175.563,-39.281]},
      "properties":{"acc":"Green","activity":"Minor volcanic unrest.",
       "hazards":"Volcanic unrest hazards.","level":1,"volcanoID":"ruapehu",
       "volcanoTitle":"Ruapehu"}},
     {"type":"Feature","geometry":{"type":"Point","coordinates":[175.641727,-39.133318]},
      "properties":{"acc":"Green","activity":"No volcanic unrest.",
       "hazards":"Volcanic environment hazards.","level":0,"volcanoID":"tongariro",
       "volcanoTitle":"Tongariro"}},
     {"type":"Feature","geometry":{"type":"Point","coordinates":[177.183,-37.521]},
      "properties":{"acc":"Orange","activity":"Minor eruption.","hazards":"Eruption hazards.",
       "level":3,"volcanoID":"whiteisland","volcanoTitle":"White Island"}},
     {"type":"Feature","geometry":null,"properties":{}}
    ]}
    """#.utf8)

    @Test("each volcano reads with its level, and a broken feature is passed over")
    func parses() throws {
        let volcanoes = try GeoNetVolcanoes.volcanoes(from: sample)
        #expect(volcanoes.map(\.id) == ["ruapehu", "tongariro", "whiteisland"])
        #expect(volcanoes[0].location.latitude == -39.281)
    }

    @Test("level 0 is no alert; unrest is a notice or caution; an eruption a danger")
    func levels() throws {
        let volcanoes = try GeoNetVolcanoes.volcanoes(from: sample)
        let alerts = volcanoes.map(GeoNetVolcanoes.alert(for:))
        #expect(alerts[0]?.kind == .information)
        #expect(alerts[0]?.title == "Ruapehu: Volcanic Alert Level 1")
        #expect(alerts[1] == nil)
        #expect(alerts[2]?.kind == .danger)
        #expect(alerts[2]?.source == .geonet)
    }
}
