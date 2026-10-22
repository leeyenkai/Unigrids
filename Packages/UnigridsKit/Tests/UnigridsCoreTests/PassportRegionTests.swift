import Testing
@testable import UnigridsCore

@Suite("Passport regions")
struct PassportRegionTests {
    @Test("the paper passport's nine regions, and only nine")
    func nineRegions() {
        #expect(PassportRegion.allCases.count == 9)
    }

    @Test("every state, district and territory is assigned")
    func assignmentIsTotal() {
        // The fallback in `byState` exists so a future state code cannot crash the
        // passport. Nothing shipping today should reach it.
        let unassigned = USState.all.filter {
            PassportRegion.stateAssignments[$0.code] == nil
        }
        #expect(unassigned.isEmpty, "unassigned: \(unassigned.map(\.code))")
    }

    @Test("each region has a distinct ink", arguments: PaletteScheme.allCases)
    func inksAreDistinct(scheme: PaletteScheme) {
        let inks = PassportRegion.allCases.map { $0.ink(scheme) }
        #expect(Set(inks).count == inks.count)
    }

    @Test("regions order the way the book binds them")
    func orderIsStable() {
        #expect(PassportRegion.northAtlantic.order == 0)
        #expect(PassportRegion.pacificNorthwestAndAlaska.order == 8)
    }

    @Test("territories are assigned, not dropped")
    func territoriesAreAssigned() {
        for territory in USState.all.filter(\.isTerritory) {
            #expect(PassportRegion.stateAssignments[territory.code] != nil)
        }
    }
}

@Suite("Passport regions against the paper book")
struct PassportRegionEvidenceTests {
    /// One park per state from the annual regional stamps, where the old guesses were
    /// wrong (the Wikipedia article on the programme, revision 1371719587).
    @Test("states file where their parks' regional stamps say")
    func evidencedStates() throws {
        let cases: [(String, PassportRegion)] = [
            ("AZ", .western), // Tumacácori, Canyon de Chelly…
            ("VA", .midAtlantic), // Colonial, Shenandoah…
            ("MD", .midAtlantic), // Antietam, Fort McHenry…
            ("SD", .rockyMountain), // Mount Rushmore, Badlands…
            ("ND", .rockyMountain), // Theodore Roosevelt…
            ("DC", .nationalCapital),
            ("AR", .southwest), // Hot Springs, Buffalo River…
        ]
        for (code, region) in cases {
            let state = try #require(USState.named(code))
            #expect(PassportRegion.byState(state) == region, "\(code)")
        }
    }
}

@Suite("Passport slots")
struct PassportSlotRuleTests {
    private let locations: [UnigridsID] = ["poi-a", "poi-b", "poi-c"]

    @Test("a stamp sits in its own location's slot")
    func ownSlot() {
        #expect(PassportSlotRule.slot(for: "poi-b", among: locations) == "poi-b")
    }

    @Test("a stamp with no location, or a vanished one, sits in the first slot only")
    func firstSlot() {
        #expect(PassportSlotRule.slot(for: nil, among: locations) == "poi-a")
        #expect(PassportSlotRule.slot(for: "poi-gone", among: locations) == "poi-a")
    }

    @Test("a site with one slot has no location to choose")
    func singleSlot() {
        #expect(PassportSlotRule.slot(for: "poi-a", among: ["poi-a"]) == nil)
        #expect(PassportSlotRule.slot(for: nil, among: []) == nil)
    }
}
