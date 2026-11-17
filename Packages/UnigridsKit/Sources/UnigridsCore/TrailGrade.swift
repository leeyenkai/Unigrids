import Foundation

/// A difficulty a trail's own authority publishes, shown as published
/// (SPECIFICATION.md §17, follow-up 15: a published rating replaces the estimate).
///
/// The five bands the catalogue filters by are Unigrids' own, so `band` is a mapping, not
/// the grade itself: the page shows the grade as its publisher wrote it and labels the
/// band as Unigrids' reading of it.
public struct TrailGrade: Hashable, Sendable, Codable {
    public enum System: String, Sendable, Codable {
        /// The Norwegian marking handbook's grades, as Kartverket's route database records
        /// them: G green (easy), B blue (medium), R red (demanding), S black (expert), and
        /// I for a route deliberately left ungraded.
        case norwegianMarking
        /// A Japanese prefecture's mountain grading (山のグレーディング): stamina from 1 to
        /// 10 and technical difficulty from A to E, written together as "3C".
        case japaneseMountainGrading
    }

    public let system: System
    /// As published: "B", "3C".
    public let grade: String
    /// Who published it: "Nagano Prefecture", "Kartverket".
    public let publisher: String?
    public let sourceURL: URL?

    public init(system: System, grade: String, publisher: String? = nil, sourceURL: URL? = nil) {
        self.system = system
        self.grade = grade
        self.publisher = publisher
        self.sourceURL = sourceURL
    }

    /// The grade in words: "Blue", "Stamina 3, technical C". Nil for a grade this build
    /// cannot read, which is then left unsaid rather than guessed.
    public var label: String? {
        switch system {
        case .norwegianMarking:
            return Self.norwegianColours[grade.uppercased()]
        case .japaneseMountainGrading:
            guard let parts = japaneseParts else { return nil }
            return "Stamina \(parts.stamina), technical \(parts.technical)"
        }
    }

    /// The band the catalogue files the trail under. A Japanese grade takes the harder of
    /// its two scales: two stamina points a band, one letter a band.
    public var band: TrailDifficulty? {
        switch system {
        case .norwegianMarking:
            return switch grade.uppercased() {
            case "G": .easy
            case "B": .moderate
            case "R": .strenuous
            case "S": .veryStrenuous
            default: nil
            }
        case .japaneseMountainGrading:
            guard let parts = japaneseParts,
                  let letter = "ABCDE".firstIndex(of: parts.technical)
            else { return nil }
            let technical = "ABCDE".distance(from: "ABCDE".startIndex, to: letter)
            let stamina = (parts.stamina - 1) / 2
            return TrailDifficulty.allCases[max(technical, stamina)]
        }
    }

    private static let norwegianColours = [
        "G": "Green", "B": "Blue", "R": "Red", "S": "Black", "I": "Not graded",
    ]

    /// "3C" read as stamina 3 and technical C; nil for anything else.
    private var japaneseParts: (stamina: Int, technical: Character)? {
        let text = grade.uppercased().filter { !$0.isWhitespace }
        guard let technical = text.last, "ABCDE".contains(technical),
              let stamina = Int(text.dropLast()), (1 ... 10).contains(stamina)
        else { return nil }
        return (stamina, technical)
    }
}
