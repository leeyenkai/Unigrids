import Foundation

/// The weather on one visit, as the stats read it from the snapshot stored with it.
public struct VisitWeather: Hashable, Sendable {
    public let placeID: UnigridsID
    public let date: Date
    public let highCelsius: Double?
    public let lowCelsius: Double?
    public let precipitationMillimetres: Double?
    /// The stored condition's name, as `WeatherCondition.name` wrote it.
    public let condition: String?

    public init(
        placeID: UnigridsID,
        date: Date,
        highCelsius: Double? = nil,
        lowCelsius: Double? = nil,
        precipitationMillimetres: Double? = nil,
        condition: String? = nil
    ) {
        self.placeID = placeID
        self.date = date
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.precipitationMillimetres = precipitationMillimetres
        self.condition = condition
    }

    var weatherCondition: WeatherCondition? {
        condition.flatMap { name in WeatherCondition.allCases.first { $0.name == name } }
    }

    /// Wet if it rained or snowed a millimetre or more, or the condition says so.
    var isWet: Bool {
        (precipitationMillimetres ?? 0) >= 1 || weatherCondition?.isWet == true
    }
}

/// The weather family of stats (SPECIFICATION.md §11): hottest, coldest and wettest
/// visits, snow days, and "fair-weather visitor or storm chaser".
public struct WeatherStats: Sendable {
    public enum Verdict: String, Sendable {
        case fairWeather
        case allWeather
        case stormChaser

        public var name: String {
            switch self {
            case .fairWeather: "Fair-weather visitor"
            case .allWeather: "All-weather visitor"
            case .stormChaser: "Storm chaser"
            }
        }

        public var detail: String {
            switch self {
            case .fairWeather: "Four visits in five or more were dry."
            case .allWeather: "Sun or rain, you went anyway."
            case .stormChaser: "Half your visits or more were wet."
            }
        }
    }

    public let measured: Int
    public let hottest: VisitWeather?
    public let coldest: VisitWeather?
    public let wettest: VisitWeather?
    public let wetVisits: Int
    public let snowVisits: Int

    /// Needs five measured visits before it says anything about the reader.
    public var verdict: Verdict? {
        guard measured >= 5 else { return nil }
        let wetShare = Double(wetVisits) / Double(measured)
        if wetShare <= 0.2 {
            return .fairWeather
        }
        if wetShare >= 0.5 {
            return .stormChaser
        }
        return .allWeather
    }

    public init(_ visits: [VisitWeather]) {
        let measured = visits.filter { $0.highCelsius != nil || $0.condition != nil }
        self.measured = measured.count
        hottest = measured.filter { $0.highCelsius != nil }
            .max { ($0.highCelsius ?? 0) < ($1.highCelsius ?? 0) }
        coldest = measured.filter { $0.lowCelsius != nil }
            .min { ($0.lowCelsius ?? 0) < ($1.lowCelsius ?? 0) }
        wettest = measured.filter { ($0.precipitationMillimetres ?? 0) > 0 }
            .max { ($0.precipitationMillimetres ?? 0) < ($1.precipitationMillimetres ?? 0) }
        wetVisits = measured.count(where: \.isWet)
        snowVisits = measured.count { $0.weatherCondition == .snow }
    }
}

extension StatsReport {
    /// Visits in each month of the year, January first, for "visits by season and month".
    public static func visitsByMonth(
        _ visits: [VisitSummary],
        calendar: Calendar = .current
    ) -> [Int] {
        var counts = Array(repeating: 0, count: 12)
        for visit in visits {
            let month = calendar.component(.month, from: visit.date)
            if (1 ... 12).contains(month) {
                counts[month - 1] += 1
            }
        }
        return counts
    }
}
