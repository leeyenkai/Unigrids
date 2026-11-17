import Testing
@testable import UnigridsCore

@Suite("Stamp pictures")
struct EmblemTests {
    @Test("path data reads as absolute segments, relative forms resolved")
    func parsesPaths() {
        let segments = SVGPathParser.parse(
            "M10 20 l5 0 h5 v-5 Q30 10 35 15 t5 5 C40 30 50 30 50 20 s10 -10 10 0 Z"
        )
        let expected: [PathSegment] = [
            .move(.init(10, 20)),
            .line(.init(15, 20)),
            .line(.init(20, 20)),
            .line(.init(20, 15)),
            .quad(control: .init(30, 10), to: .init(35, 15)),
            .quad(control: .init(40, 20), to: .init(40, 20)),
            .cubic(control1: .init(40, 30), control2: .init(50, 30), to: .init(50, 20)),
            .cubic(control1: .init(50, 10), control2: .init(60, 10), to: .init(60, 20)),
            .close,
        ]
        #expect(segments == expected)
    }

    @Test("compact numbers and implicit line-tos read as SVG means them")
    func compactNumbers() {
        let compact: [PathSegment] = [
            .move(.init(0, 0)), .line(.init(1, -1.5)), .line(.init(0.5, 0.5)),
        ]
        #expect(SVGPathParser.parse("M0 0 1-1.5.5.5") == compact)
        let relative: [PathSegment] = [.move(.init(1, 1)), .line(.init(3, 3))]
        #expect(SVGPathParser.parse("m1 1 2 2") == relative)
    }

    @Test("an unknown command ends the path rather than guessing at it")
    func unknownCommand() {
        let kept: [PathSegment] = [.move(.init(0, 0)), .line(.init(5, 5))]
        #expect(SVGPathParser.parse("M0 0 L5 5 A1 1 0 0 1 9 9") == kept)
    }

    @Test("every kind of place has a motif, and a place's own picture wins")
    func motifs() {
        let park = Place(
            id: "np-yosemite", name: "Yosemite", designation: "National Park",
            kind: .nationalPark, states: [], centre: .init(latitude: 37.8, longitude: -119.5),
            emblem: "np-yosemite"
        )
        #expect(EmblemMotif.key(for: park) == "np-yosemite")
        #expect(EmblemMotif.motifKey(for: park) == "motif-peaks")
        let lighthouse = Place(
            id: "nps-caha", name: "Cape Hatteras", designation: "National Seashore",
            kind: .npsUnit, states: [], centre: .init(latitude: 35.2, longitude: -75.5)
        )
        #expect(EmblemMotif.key(for: lighthouse) == "motif-lighthouse")
    }
}
