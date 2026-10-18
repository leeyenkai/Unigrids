import Testing
@testable import UnigridsCore

@Suite("Guide panels")
struct GuidePanelTests {
    @Test("panels appear in template order")
    func templateOrder() {
        let guide = GuideContent(
            placeID: "np-zion",
            story: ["one", "two"],
            trailHighlightIDs: ["trail-a"],
            planYourVisit: PlanYourVisit(entrances: ["South"]),
            chronology: [ChronologyEntry(year: "1919", text: "Established")],
            safety: ["Flash floods"],
            credits: ["NPS"]
        )
        let panels = guide.panels(
            placeHasFacts: true,
            sightCount: 8,
            visitorCentreCount: 2,
            hasTrails: true
        )
        #expect(panels.map(\.id) == [
            "at-a-glance", "story", "major-sights", "visitor-centres",
            "trail-highlights", "plan-your-visit", "chronology", "safety", "credits",
        ])
    }

    @Test("a panel with nothing in it is not rendered")
    func emptyPanelsAreSkipped() {
        let guide = GuideContent(placeID: "np-x")
        let panels = guide.panels(
            placeHasFacts: false,
            sightCount: 0,
            visitorCentreCount: 0,
            hasTrails: false
        )
        #expect(panels.isEmpty)
    }

    @Test("trail highlights wait for the catalogue")
    func trailPanelNeedsTrails() {
        // The guide lists trail highlights by id, but the panel must not appear before
        // the catalogue exists to link into (docs/mvp-scope.md).
        let guide = GuideContent(placeID: "np-x", trailHighlightIDs: ["trail-a"])
        let panels = guide.panels(
            placeHasFacts: false,
            sightCount: 0,
            visitorCentreCount: 0,
            hasTrails: false
        )
        #expect(!panels.contains(.trailHighlights))
    }

    @Test("images and prose ask for more columns than lists")
    func columnSpans() {
        #expect(GuidePanel.story.preferredColumnSpan == 2)
        #expect(GuidePanel.chronology.preferredColumnSpan == 1)
    }
}
