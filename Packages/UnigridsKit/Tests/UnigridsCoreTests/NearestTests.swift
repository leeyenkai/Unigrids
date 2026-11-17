import Testing
@testable import UnigridsCore

@Suite("Nearest places")
struct NearestTests {
    private func place(_ id: String, _ latitude: Double, _ longitude: Double) -> Place {
        Place(
            id: UnigridsID(id), name: id, designation: "National Park", kind: .nationalPark,
            states: [], centre: Coordinate(latitude: latitude, longitude: longitude),
            country: .japan
        )
    }

    @Test("places come nearest first, from Sapporo")
    func order() {
        let sapporo = Coordinate(latitude: 43.06, longitude: 141.35)
        let parks = [
            place("jp-np-yakushima", 30.35, 130.53),
            place("jp-np-shikotsu-toya", 42.77, 141.2),
            place("jp-np-shiretoko", 44.08, 145.12),
        ]
        let nearest = parks.nearest(to: sapporo)
        #expect(nearest.map(\.place.id.rawValue)
            == ["jp-np-shikotsu-toya", "jp-np-shiretoko", "jp-np-yakushima"])
        #expect(nearest[0].metres > 30000 && nearest[0].metres < 40000)
    }
}
