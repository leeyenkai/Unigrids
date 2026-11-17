import Testing
import UnigridsCore
@testable import UnigridsReference

/// The stamps' pictures as bundled: every national park its own, every other place its
/// kind's motif, and every drawing one the app can draw.
@Suite("Bundled stamp pictures")
struct BundledEmblemTests {
    private let store: BundledReferenceStore

    init() throws {
        store = try SharedBundle.store.get()
    }

    @Test("every national park has a drawing of its own")
    func parksHaveTheirOwn() {
        for park in store.nationalParks {
            #expect(park.emblem == park.id.rawValue, "\(park.id) has no picture of its own")
            #expect(store.emblems[park.id.rawValue] != nil, "\(park.id)'s picture is missing")
        }
    }

    @Test("every place resolves to a picture")
    func everyPlaceResolves() {
        let missing = store.places.filter { store.emblem(for: $0) == nil }
        #expect(missing.isEmpty, "\(missing.prefix(5).map(\.id))")
    }

    @Test("every drawing parses, stays on its canvas and says what it shows")
    func drawingsAreSound() {
        for (key, emblem) in store.emblems {
            #expect(!emblem.subject.isEmpty, "\(key)")
            for part in emblem.parts {
                let segments = part.segments
                #expect(!segments.isEmpty, "\(key): a part draws nothing")
                for segment in segments {
                    let points: [EmblemPoint] = switch segment {
                    case let .move(point), let .line(point): [point]
                    case let .quad(control, to): [control, to]
                    case let .cubic(first, second, to): [first, second, to]
                    case .close: []
                    }
                    for point in points {
                        #expect((-2 ... emblem.width + 2).contains(point.x), "\(key) off canvas")
                        #expect((-2 ... emblem.height + 2).contains(point.y), "\(key) off canvas")
                    }
                }
            }
        }
    }
}
