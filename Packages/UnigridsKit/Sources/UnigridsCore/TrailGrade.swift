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
        /// New Zealand's Department of Conservation track categories, from a
        /// wheelchair-accessible short walk to an expert route.
        case newZealandTrackCategory
        /// Parks Canada's summer difficulty rating: Easy, Moderate, Difficult, Most
        /// difficult.
        case parksCanadaDifficulty
        /// The Australian Walking Track Grading System's grades 1 to 5, as Queensland
        /// publishes them ("Track class 3 to AS 2156.1").
        case australianWalkingTrackGrade
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
        case .newZealandTrackCategory:
            return Self.trackCategories[grade] == nil ? nil : grade
        case .parksCanadaDifficulty:
            return Self.parksCanadaRatings[grade] == nil ? nil : grade
        case .australianWalkingTrackGrade:
            return Self.australianGrades[grade] == nil ? nil : "Grade \(grade)"
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
        case .newZealandTrackCategory:
            return Self.trackCategories[grade]
        case .parksCanadaDifficulty:
            return Self.parksCanadaRatings[grade]
        case .australianWalkingTrackGrade:
            return Self.australianGrades[grade]
        }
    }

    /// DOC's six categories, read into the catalogue's bands.
    private static let trackCategories: [String: TrailDifficulty] = [
        "Wheelchair-accessible short walk": .easy,
        "Easy short walk": .easy,
        "Easy to intermediate walking track": .moderate,
        "Intermediate tramping track": .moderatelyStrenuous,
        "Advanced tramping track": .strenuous,
        "Expert route": .veryStrenuous,
    ]

    /// Parks Canada's four ratings, read into the catalogue's bands: its Difficult is a
    /// strenuous day, its Most difficult the hardest band.
    private static let parksCanadaRatings: [String: TrailDifficulty] = [
        "Easy": .easy,
        "Moderate": .moderate,
        "Difficult": .strenuous,
        "Most difficult": .veryStrenuous,
    ]

    /// The Australian standard's five grades, read into the catalogue's bands: 1 and 2
    /// need no experience, 3 suits most fit walkers, 4 calls for experience and 5 for
    /// specialised skills.
    private static let australianGrades: [String: TrailDifficulty] = [
        "1": .easy, "2": .easy, "3": .moderate, "4": .strenuous, "5": .veryStrenuous,
    ]

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
