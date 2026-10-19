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

    @Test("the new panels take their places in the template")
    func extendedTemplate() {
        let image = GuideImage(assetName: "a.jpg", credit: "NPS", isPublicDomain: true)
        let guide = GuideContent(
            placeID: "np-zion",
            hero: image,
            story: ["one"],
            planYourVisit: PlanYourVisit(),
            gallery: [image],
            fees: [EntranceFee(title: "Private vehicle", cost: "$35")],
            weather: "Hot in summer.",
            directions: "From Interstate 15."
        )
        let panels = guide.panels(
            placeHasFacts: true,
            sightCount: 3,
            visitorCentreCount: 1,
            hasTrails: false,
            hasMap: true,
            showsAlerts: true
        )
        #expect(panels.map(\.id) == [
            "hero", "at-a-glance", "story", "gallery", "park-map", "major-sights",
            "visitor-centres", "alerts", "plan-your-visit", "weather", "getting-there",
        ])
    }

    @Test("fees alone are enough for a plan-your-visit panel")
    func feesMakeAPlanPanel() {
        let guide = GuideContent(
            placeID: "np-x",
            fees: [EntranceFee(title: "Per person", cost: "$15")]
        )
        let panels = guide.panels(
            placeHasFacts: false, sightCount: 0, visitorCentreCount: 0, hasTrails: false
        )
        #expect(panels.map(\.id) == ["plan-your-visit"])
    }

    @Test("a photo credit reads as one, with the licence where there is one")
    func creditLine() {
        #expect(
            GuideImage(credit: "NPS / Jacob W. Frank", isPublicDomain: true).creditLine
                == "Photo: NPS / Jacob W. Frank"
        )
        #expect(
            GuideImage(credit: "Jane Doe", isPublicDomain: false, licence: "CC BY-SA 4.0")
                .creditLine
                == "Photo: Jane Doe · CC BY-SA 4.0"
        )
    }
}
