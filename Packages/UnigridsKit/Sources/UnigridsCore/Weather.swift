import Foundation

/// A day's weather at a place: forecast for a trip, or history for a visit
/// (SPECIFICATION.md §10, §11).
public struct DailyWeather: Hashable, Sendable {
    public let date: String
    public let code: Int?
    public let highCelsius: Double?
    public let lowCelsius: Double?
    /// Total precipitation, for a day that has happened.
    public let precipitationMillimetres: Double?
    /// Chance of precipitation, for a forecast day.
    public let precipitationProbability: Double?
    public let sunrise: String?
    public let sunset: String?

    public var condition: WeatherCondition? {
        code.map(WeatherCondition.init(code:))
    }

    public init(
        date: String,
        code: Int? = nil,
        highCelsius: Double? = nil,
        lowCelsius: Double? = nil,
        precipitationMillimetres: Double? = nil,
        precipitationProbability: Double? = nil,
        sunrise: String? = nil,
        sunset: String? = nil
    ) {
        self.date = date
        self.code = code
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.precipitationMillimetres = precipitationMillimetres
        self.precipitationProbability = precipitationProbability
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// The WMO weather interpretation codes Open-Meteo reports, grouped into the handful of
/// conditions worth a word and an icon.
public enum WeatherCondition: String, Sendable, CaseIterable {
    case clear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm
    case unknown

    public init(code: Int) {
        self = switch code {
        case 0, 1: .clear
        case 2: .partlyCloudy
        case 3: .overcast
        case 45, 48: .fog
        case 51 ... 57: .drizzle
        case 61 ... 67: .rain
        case 71 ... 77, 85, 86: .snow
        case 80 ... 82: .showers
        case 95 ... 99: .thunderstorm
        default: .unknown
        }
    }

    public var name: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .showers: "Showers"
        case .thunderstorm: "Thunderstorms"
        case .unknown: "Mixed"
        }
    }

    /// Whether the day counts as wet for "fair-weather visitor or storm chaser".
    public var isWet: Bool {
        switch self {
        case .drizzle, .rain, .snow, .showers, .thunderstorm: true
        default: false
        }
    }
}

/// Open-Meteo's daily response, decoded. The same shape answers the forecast and the
/// historical archive, with a field or two present in one and not the other.
public struct OpenMeteoDaily: Decodable, Sendable {
    private struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int?]?
        let high: [Double?]?
        let low: [Double?]?
        let precipitation: [Double?]?
        let precipitationProbability: [Double?]?
        let sunrise: [String?]?
        let sunset: [String?]?

        private enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case high = "temperature_2m_max"
            case low = "temperature_2m_min"
            case precipitation = "precipitation_sum"
            case precipitationProbability = "precipitation_probability_max"
            case sunrise
            case sunset
        }
    }

    private let daily: Daily

    public var days: [DailyWeather] {
        daily.time.enumerated().map { index, date in
            DailyWeather(
                date: date,
                code: Self.value(daily.weatherCode, index),
                highCelsius: Self.value(daily.high, index),
                lowCelsius: Self.value(daily.low, index),
                precipitationMillimetres: Self.value(daily.precipitation, index),
                precipitationProbability: Self.value(daily.precipitationProbability, index),
                sunrise: Self.value(daily.sunrise, index),
                sunset: Self.value(daily.sunset, index)
            )
        }
    }

    private static func value<T>(_ series: [T?]?, _ index: Int) -> T? {
        guard let series, series.indices.contains(index) else { return nil }
        return series[index]
    }

    /// The day matching an ISO `yyyy-MM-dd` date.
    public func day(_ date: String) -> DailyWeather? {
        days.first { $0.date == date }
    }
}

extension DailyWeather {
    /// `yyyy-MM-dd` for a date in a calendar, the form Open-Meteo keys its days by.
    public static func key(
        for date: Date,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 1970,
            parts.month ?? 1,
            parts.day ?? 1
        )
    }
}

/// A park's climate by month: mean daily high and low, mean monthly precipitation
/// (SPECIFICATION.md §10, "Best time to visit"). Ten years of reanalysis at the park's
/// centre point, which in a big mountain park is one elevation of many.
public struct MonthlyClimate: Hashable, Sendable {
    public struct Month: Hashable, Sendable, Identifiable {
        /// 1 to 12.
        public let month: Int
        public let highCelsius: Double
        public let lowCelsius: Double
        public let precipitationMillimetres: Double

        public var id: Int {
            month
        }
    }

    /// "2016–2025".
    public let period: String
    public let months: [Month]

    public init(period: String, months: [Month]) {
        self.period = period
        self.months = months
    }

    /// The warmest and the driest months, for a line under the chart.
    public var warmest: Month? {
        months.max { $0.highCelsius < $1.highCelsius }
    }

    public var coldest: Month? {
        months.min { $0.lowCelsius < $1.lowCelsius }
    }

    public var wettest: Month? {
        months.max { $0.precipitationMillimetres < $1.precipitationMillimetres }
    }
}

extension MonthlyClimate: Codable {
    private enum CodingKeys: String, CodingKey {
        case period
        case months
    }

    /// `{"period": "2016–2025", "months": [[high, low, precipitation] × 12]}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decode(String.self, forKey: .period)
        let rows = try container.decode([[Double]].self, forKey: .months)
        months = rows.enumerated().compactMap { index, row in
            guard row.count == 3 else { return nil }
            return Month(
                month: index + 1,
                highCelsius: row[0],
                lowCelsius: row[1],
                precipitationMillimetres: row[2]
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(
            months.map { [$0.highCelsius, $0.lowCelsius, $0.precipitationMillimetres] },
            forKey: .months
        )
    }
}
