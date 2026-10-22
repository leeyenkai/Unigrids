import Foundation
import Testing
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
