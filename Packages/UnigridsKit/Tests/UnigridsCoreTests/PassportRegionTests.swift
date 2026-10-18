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
