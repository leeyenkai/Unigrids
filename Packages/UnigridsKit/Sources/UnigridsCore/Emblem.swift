import Foundation

/// The picture a passport stamp carries in its centre band (SPECIFICATION.md §9): a
/// park's own landmark, animal or sky — Half Dome, a polar bear on the ice, Uluṟu — drawn
/// as original line art in one ink, or a shared motif for a place without one of its own.
///
/// Drawings are authored as SVG path data on a fixed canvas (`Pipeline/content/emblems/`)
/// and bundled in `emblems.json`. Core holds them as plain geometry, so the rules that
/// read them test without SwiftUI; `UnigridsDesign` turns them into shapes.
public struct Emblem: Hashable, Sendable, Codable {
    /// One drawn element: a line, or a solid area.
    public struct Part: Hashable, Sendable, Codable {
        /// SVG path data: `M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T` and `Z`, absolute or
        /// relative.
        public let d: String // swiftlint:disable:this identifier_name
        /// Filled solid, or stroked as a line.
        public let fill: Bool

        public init(d: String, fill: Bool) { // swiftlint:disable:this identifier_name
            self.d = d
            self.fill = fill
        }

        /// The part's geometry, parsed once per use.
        public var segments: [PathSegment] {
            SVGPathParser.parse(d)
        }
    }

    /// What the picture shows, for VoiceOver: "a polar bear on sea ice".
    public let subject: String
    /// The canvas the parts are drawn on, in its own units.
    public let width: Double
    public let height: Double
    public let parts: [Part]

    public init(subject: String, width: Double, height: Double, parts: [Part]) {
        self.subject = subject
        self.width = width
        self.height = height
        self.parts = parts
    }
}

/// One step of a drawn path, in absolute canvas coordinates.
public enum PathSegment: Hashable, Sendable {
    case move(EmblemPoint)
    case line(EmblemPoint)
    case quad(control: EmblemPoint, to: EmblemPoint)
    case cubic(control1: EmblemPoint, control2: EmblemPoint, to: EmblemPoint)
    case close
}

public struct EmblemPoint: Hashable, Sendable {
    public let x: Double // swiftlint:disable:this identifier_name
    public let y: Double // swiftlint:disable:this identifier_name

    public init(_ x: Double, _ y: Double) { // swiftlint:disable:this identifier_name
        self.x = x
        self.y = y
    }
}

/// A small SVG path data reader: enough of the grammar for line art drawn by hand —
/// moves, lines, horizontal and vertical lines, cubic and quadratic curves with their
/// smooth forms, and close — in absolute or relative form. Anything else ends the path
/// rather than guessing at it.
public enum SVGPathParser {
    public static func parse(_ data: String) -> [PathSegment] {
        var reader = Reader(Array(data.unicodeScalars))
        var segments: [PathSegment] = []
        var state = State()
        var command: Unicode.Scalar?
        while true {
            reader.skipSeparators()
            guard let next = reader.peek() else { break }
            if next.properties.isAlphabetic {
                command = reader.take()
            } else if command == nil {
                break
            }
            guard let current = command,
                  let produced = step(current, &reader, &state)
            else { break }
            segments += produced
            // A move's implicit repeats are lines.
            if current == "M" {
                command = "L"
            } else if current == "m" {
                command = "l"
            } else if current == "Z" || current == "z" {
                command = nil
            }
        }
        return segments
    }

    private struct State {
        var current = EmblemPoint(0, 0)
        var start = EmblemPoint(0, 0)
        /// The last control point, for the smooth curve forms.
        var lastCubicControl: EmblemPoint?
        var lastQuadControl: EmblemPoint?
    }

    /// A command and its operands. Returns nil when the operands are missing or malformed.
    private static func step(
        _ command: Unicode.Scalar, _ reader: inout Reader, _ state: inout State
    ) -> [PathSegment]? {
        let relative = command.properties.isLowercase
        func point() -> EmblemPoint? {
            guard let across = reader.number(), let down = reader.number() else { return nil }
            return relative ? EmblemPoint(state.current.x + across, state.current.y + down)
                : EmblemPoint(across, down)
        }
        switch Character(command).uppercased() {
        case "M":
            guard let to = point() else { return nil }
            state.current = to
            state.start = to
            state.lastCubicControl = nil
            state.lastQuadControl = nil
            return [.move(to)]
        case "L":
            guard let to = point() else { return nil }
            state.current = to
            state.lastCubicControl = nil
            state.lastQuadControl = nil
            return [.line(to)]
        case "H":
            guard let across = reader.number() else { return nil }
            let to = EmblemPoint(relative ? state.current.x + across : across, state.current.y)
            state.current = to
            state.lastCubicControl = nil
            state.lastQuadControl = nil
            return [.line(to)]
        case "V":
            guard let down = reader.number() else { return nil }
            let to = EmblemPoint(state.current.x, relative ? state.current.y + down : down)
            state.current = to
            state.lastCubicControl = nil
            state.lastQuadControl = nil
            return [.line(to)]
        case "C":
            guard let first = point(), let second = point(), let to = point() else {
                return nil
            }
            state.current = to
            state.lastCubicControl = second
            state.lastQuadControl = nil
            return [.cubic(control1: first, control2: second, to: to)]
        case "S":
            let first = reflect(state.lastCubicControl, about: state.current)
            guard let second = point(), let to = point() else { return nil }
            state.current = to
            state.lastCubicControl = second
            state.lastQuadControl = nil
            return [.cubic(control1: first, control2: second, to: to)]
        case "Q":
            guard let control = point(), let to = point() else { return nil }
            state.current = to
            state.lastQuadControl = control
            state.lastCubicControl = nil
            return [.quad(control: control, to: to)]
        case "T":
            let control = reflect(state.lastQuadControl, about: state.current)
            guard let to = point() else { return nil }
            state.current = to
            state.lastQuadControl = control
            state.lastCubicControl = nil
            return [.quad(control: control, to: to)]
        case "Z":
            state.current = state.start
            state.lastCubicControl = nil
            state.lastQuadControl = nil
            return [.close]
        default:
            return nil
        }
    }

    private static func reflect(_ control: EmblemPoint?, about point: EmblemPoint) -> EmblemPoint {
        guard let control else { return point }
        return EmblemPoint(2 * point.x - control.x, 2 * point.y - control.y)
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        func peek() -> Unicode.Scalar? {
            index < scalars.count ? scalars[index] : nil
        }

        mutating func take() -> Unicode.Scalar? {
            defer { index += 1 }
            return peek()
        }

        mutating func skipSeparators() {
            while let scalar = peek(), scalar == "," || scalar.properties.isWhitespace {
                index += 1
            }
        }

        /// A number in SVG's grammar: sign, digits, one decimal point, an exponent. A
        /// second point starts the next number, as `0.5.5` means `0.5 .5`.
        mutating func number() -> Double? {
            skipSeparators()
            var text = ""
            var seenPoint = false
            var seenExponent = false
            while let scalar = peek() {
                let isSign = scalar == "-" || scalar == "+"
                let afterExponent = text.last == "e" || text.last == "E"
                if isSign, !text.isEmpty, !afterExponent {
                    break
                }
                if scalar == "." {
                    if seenPoint || seenExponent {
                        break
                    }
                    seenPoint = true
                } else if scalar == "e" || scalar == "E" {
                    if seenExponent || text.isEmpty {
                        break
                    }
                    seenExponent = true
                } else if !isSign, !("0" ... "9").contains(scalar) {
                    break
                }
                text.unicodeScalars.append(scalar)
                index += 1
            }
            return Double(text)
        }
    }
}

/// The motif a place without a drawing of its own carries, from what kind of place it is,
/// so no stamp is ever blank. A national park always has its own drawing; the bundled-data
/// tests hold every one to that.
public enum EmblemMotif {
    /// The place's own picture if it has one, else its kind's motif.
    public static func key(for place: Place) -> String {
        place.emblem ?? motifKey(for: place)
    }

    /// The shared motif for the place's kind, whatever picture it names.
    public static func motifKey(for place: Place) -> String {
        let motif = switch place.siteType {
        case .nationalPark, .nationalPreserve, .protectedLandscape: "peaks"
        case .nationalMonument: "monument"
        case .historicSite: "house"
        case .battlefield: "cannon"
        case .memorial: "memorial"
        case .seashore, .marineConservationArea: "lighthouse"
        case .recreationArea: "lake"
        case .river: "river"
        case .parkway, .scenicByway: "road"
        case .otherNPSSite: "flag"
        case .statePark, .stateNationalPark, .provincialPark, .quasiNationalPark: "trees"
        case .nationalForest, .conservationPark: "forest"
        case .nationalGrassland: "prairie"
        case .wildlifeRefuge, .natureReserve: "marsh"
        case .conservationArea: "mesa"
        case .naturalLandmark: "rock"
        }
        return "motif-\(motif)"
    }
}
