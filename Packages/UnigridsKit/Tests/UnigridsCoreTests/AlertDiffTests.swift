import Testing
@testable import UnigridsCore

@Suite("Alert notifications")
struct AlertDiffTests {
    private let closure = AlertDiff.Alert(id: "a1", parkCode: "ZION", isUrgent: true)
    private let caution = AlertDiff.Alert(id: "a2", parkCode: "zion", isUrgent: false)

    @Test("a park looked at for the first time is taken in without a word")
    func firstLook() {
        let result = AlertDiff.check([closure, caution], watching: ["zion"], seen: .init())
        #expect(result.notify.isEmpty)
        #expect(result.seen == .init(parks: ["zion"], alerts: ["a1", "a2"]))
    }

    @Test("a new danger or closure at a watched park is news; a caution is not")
    func newUrgent() {
        let seen = AlertDiff.Seen(parks: ["zion"], alerts: [])
        let result = AlertDiff.check([closure, caution], watching: ["zion"], seen: seen)
        #expect(result.notify == [closure])
    }

    @Test("an alert already seen is not told twice")
    func seenOnce() {
        let seen = AlertDiff.Seen(parks: ["zion"], alerts: ["a1"])
        #expect(AlertDiff.check([closure], watching: ["zion"], seen: seen).notify.isEmpty)
    }

    @Test("a park that leaves the watch and comes back is taken in afresh")
    func rewatched() {
        let left = AlertDiff.check([], watching: [], seen: .init(parks: ["zion"], alerts: []))
        #expect(left.seen.parks.isEmpty)
        let back = AlertDiff.check([closure], watching: ["zion"], seen: left.seen)
        #expect(back.notify.isEmpty)
    }
}
