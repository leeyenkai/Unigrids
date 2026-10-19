import Testing
@testable import UnigridsCore

@Suite("App icon choice")
struct AppIconChoiceTests {
    @Test("the shipping icon has no alternate name, and every other one does")
    func alternateNames() {
        // `setAlternateIconName(nil)` is how UIKit is told to go back to the primary
        // icon, so the default case must map to nil and nothing else may.
        #expect(AppIconChoice.standard.alternateIconName == nil)
        for choice in AppIconChoice.allCases where choice != .standard {
            #expect(choice.alternateIconName == "AppIcon-\(choice.rawValue)")
        }
    }

    @Test("a name round-trips back to its choice", arguments: AppIconChoice.allCases)
    func namesRoundTrip(choice: AppIconChoice) {
        #expect(AppIconChoice.named(choice.alternateIconName) == choice)
    }

    @Test("an icon the app no longer ships reads as the default")
    func unknownNameFallsBack() {
        // A reader who picked an icon that a later release removed should land on the
        // default rather than on a row the picker cannot show.
        #expect(AppIconChoice.named("AppIcon-badlands") == .standard)
        #expect(AppIconChoice.named("") == .standard)
    }

    @Test("every icon names a park and a state")
    func everyChoiceIsLabelled() {
        for choice in AppIconChoice.allCases {
            #expect(!choice.name.isEmpty)
            #expect(!choice.state.isEmpty)
        }
    }

    @Test("stored raw values are a format, not an implementation detail")
    func rawValuesAreStable() {
        // These sit in UserDefaults, and they are also half of the asset-catalogue
        // names the Xcode target registers. Renaming a case breaks both.
        #expect(AppIconChoice.allCases.map(\.rawValue) == [
            "zion", "grandCanyon", "yosemite", "sequoia", "rockyMountain",
            "olympic", "acadia", "joshuaTree", "everglades", "congaree",
        ])
    }
}
