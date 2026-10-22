import MapKit
import Observation
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference
import UserNotifications

// The planner's tools on top of a trip (SPECIFICATION.md §10): drive times between stops
// from MapKit directions, a day total and a warning when a day is overloaded, flags for a
// stop that has a closure posted or needs a reservation, forecasts for the days the trip
// is near enough to forecast, and reminders for permit and booking windows.

// MARK: - Drive times

/// One leg as MapKit routed it: time, road distance and the road itself.
struct RoutedLeg: Equatable {
    let seconds: Double
    let metres: Double
    let path: [Coordinate]
}

/// Drive times between stops, asked of MapKit once per pair and kept for the session.
///
/// Directions need a connection and are rate-limited by Apple, so a leg that cannot be
/// routed — an island, a park with no road, no signal — stays unrouted and the trip shows
/// its straight-line distance instead, labelled as such.
@MainActor
@Observable
final class DriveTimes {
    private(set) var legs: [String: RoutedLeg] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []

    static func key(_ from: UnigridsID, _ to: UnigridsID) -> String {
        "\(from.rawValue)>\(to.rawValue)"
    }

    func leg(from: UnigridsID, to: UnigridsID) -> RoutedLeg? {
        legs[Self.key(from, to)]
    }

    func hasFailed(from: UnigridsID, to: UnigridsID) -> Bool {
        failed.contains(Self.key(from, to))
    }

    /// Route every consecutive pair not yet routed, one at a time.
    ///
    /// A park's centre can be twenty miles from a road, so each leg runs between the
    /// visitor centres that face each other — the one nearest the next park, to the one
    /// nearest the last — and falls back to the centre where a place has none.
    func route(_ places: [Place], store: any ReferenceStore) async {
        for (from, to) in zip(places, places.dropFirst()) {
            let key = Self.key(from.id, to.id)
            guard legs[key] == nil, !failed.contains(key), !inFlight.contains(key) else { continue }
            inFlight.insert(key)
            defer { inFlight.remove(key) }
            let start = Self.anchor(of: from, toward: to.centre, store: store)
            let end = Self.anchor(of: to, toward: start, store: store)
            let request = MKDirections.Request()
            request.source = Self.item(at: start, named: from.name)
            request.destination = Self.item(at: end, named: to.name)
            request.transportType = .automobile
            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else {
                    failed.insert(key)
                    continue
                }
                legs[key] = RoutedLeg(
                    seconds: route.expectedTravelTime,
                    metres: route.distance,
                    path: Self.coordinates(of: route.polyline)
                )
            } catch {
                failed.insert(key)
            }
        }
    }

    private static func anchor(
        of place: Place, toward point: Coordinate, store: any ReferenceStore
    ) -> Coordinate {
        store.visitorCentres(in: place.id)
            .min { $0.location.distance(to: point) < $1.location.distance(to: point) }?
            .location ?? place.centre
    }

    private static func item(at point: Coordinate, named name: String) -> MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: point.latitude, longitude: point.longitude),
            address: nil
        )
        item.name = name
        return item
    }

    private static func coordinates(of polyline: MKPolyline) -> [Coordinate] {
        var points = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: polyline.pointCount
        )
        polyline.getCoordinates(&points, range: NSRange(location: 0, length: polyline.pointCount))
        // A route can carry tens of thousands of points; one in every few is plenty for
        // a trip's overview map.
        let step = max(1, points.count / 600)
        return stride(from: 0, to: points.count, by: step).map {
            Coordinate(latitude: points[$0].latitude, longitude: points[$0].longitude)
        } + (points.last.map { [Coordinate(latitude: $0.latitude, longitude: $0.longitude)] } ?? [])
    }
}

// MARK: - Forecasts

/// Sixteen-day forecasts from Open-Meteo, per place, kept for an hour.
///
/// The request carries a park's coordinates and nothing about the reader (§15).
@MainActor
@Observable
final class Forecasts {
    private(set) var byPlace: [UnigridsID: OpenMeteoDaily] = [:]
    private var fetchedAt: [UnigridsID: Date] = [:]

    func forecast(for place: Place, on date: Date) -> DailyWeather? {
        byPlace[place.id]?.day(DailyWeather.key(for: date))
    }

    func load(_ places: [Place]) async {
        for place in places {
            if let at = fetchedAt[place.id], Date().timeIntervalSince(at) < 3600 {
                continue
            }
            if let daily = await OpenMeteo.forecast(at: place.centre) {
                byPlace[place.id] = daily
                fetchedAt[place.id] = Date()
            }
        }
    }
}

/// Open-Meteo's forecast and historical archive. Free for non-commercial use, data under
/// CC BY 4.0, credited in Attributions (SPECIFICATION.md §12).
enum OpenMeteo {
    static func forecast(at point: Coordinate) async -> OpenMeteoDaily? {
        await request("https://api.open-meteo.com/v1/forecast", point: point, extra: [
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,"
                    + "precipitation_probability_max,sunrise,sunset"
            ),
            URLQueryItem(name: "forecast_days", value: "16"),
        ])
    }

    /// The weather on a past day. The archive lags by about five days, so a recent day is
    /// asked of the forecast service's own short history instead.
    static func history(
        at point: Coordinate,
        on date: Date
    ) async -> (DailyWeather, recent: Bool)? {
        let key = DailyWeather.key(for: date)
        let age = Date().timeIntervalSince(date)
        guard age > -3600 else { return nil }
        let daily = "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"
        if age < 6 * 86400 {
            let result = await request(
                "https://api.open-meteo.com/v1/forecast",
                point: point,
                extra: [
                    URLQueryItem(name: "daily", value: daily),
                    URLQueryItem(name: "past_days", value: "7"),
                    URLQueryItem(name: "forecast_days", value: "1"),
                ]
            )
            return result?.day(key).map { ($0, true) }
        }
        let result = await request(
            "https://archive-api.open-meteo.com/v1/archive",
            point: point,
            extra: [
                URLQueryItem(name: "daily", value: daily),
                URLQueryItem(name: "start_date", value: key),
                URLQueryItem(name: "end_date", value: key),
            ]
        )
        return result?.day(key).map { ($0, false) }
    }

    private static func request(
        _ base: String, point: Coordinate, extra: [URLQueryItem]
    ) async -> OpenMeteoDaily? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", point.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", point.longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
        ] + extra
        guard let url = components.url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(OpenMeteoDaily.self, from: data)
    }
}

/// A day's forecast in a line: icon, high and low, chance of rain.
struct ForecastLine: View {
    @Environment(\.unigrid) private var style
    let weather: DailyWeather

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: weather.condition.map(WeatherSymbol.name) ?? "cloud")
                .symbolRenderingMode(.multicolor)
            if let high = weather.highCelsius, let low = weather.lowCelsius {
                Text(
                    UnigridsFormat.temperature(celsius: high) + " / "
                        + UnigridsFormat.temperature(celsius: low)
                )
                .monospacedDigit()
            }
            if let chance = weather.precipitationProbability, chance >= 20 {
                Text("\(Int(chance))% rain")
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .font(UnigridStyle.rowDetail)
        .foregroundStyle(style.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Forecast: \(weather.condition?.name ?? "unknown")"
                +
                (weather.highCelsius
                    .map { ", high \(UnigridsFormat.temperature(celsius: $0))" } ?? "")
        )
    }
}

/// SF Symbols for weather conditions.
enum WeatherSymbol {
    static func name(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .showers: "cloud.heavyrain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "cloud.sun"
        }
    }
}

// MARK: - Flags

/// Something worth knowing about a stop before the day comes.
enum StopFlag: Hashable, Identifiable {
    case alert(kind: String, title: String, isDanger: Bool)
    case reservations(String)
    case seasonalClosures([String])

    var id: String {
        switch self {
        case let .alert(_, title, _): "alert-\(title)"
        case .reservations: "reservations"
        case .seasonalClosures: "seasonal"
        }
    }

    var symbol: String {
        switch self {
        case .alert: "exclamationmark.triangle.fill"
        case .reservations: "ticket"
        case .seasonalClosures: "snowflake"
        }
    }

    var title: String {
        switch self {
        case let .alert(kind, title, _): "\(kind) posted: \(title)"
        case .reservations: "Reservations or permits may be needed"
        case .seasonalClosures: "Seasonal closures around this date"
        }
    }

    var detail: String? {
        switch self {
        case .alert: nil
        case let .reservations(text): text
        case let .seasonalClosures(lines): lines.joined(separator: " ")
        }
    }

    /// The flags for a stop: live closure and danger alerts, the guide's reservation note,
    /// and its seasonal closures when the stop falls in the closure months.
    @MainActor
    static func flags(
        for place: Place,
        on date: Date?,
        alerts: AlertsCenter?,
        guide: GuideContent?
    ) -> [StopFlag] {
        var flags: [StopFlag] = []
        let posted = alerts?.alerts(for: place.npsParkCode) ?? []
        for alert in posted where alert.kind == .closure || alert.kind == .danger {
            flags.append(.alert(
                kind: alert.kind.name,
                title: alert.title,
                isDanger: alert.kind == .danger
            ))
        }
        if let reservations = guide?.planYourVisit.reservations {
            flags.append(.reservations(reservations))
        }
        let closures = guide?.planYourVisit.seasonalClosures ?? []
        if let date, TripSchedule.isClosureSeason(date), !closures.isEmpty {
            flags.append(.seasonalClosures(closures))
        }
        return flags
    }
}

/// A stop's flags, as rows under it.
struct StopFlagList: View {
    @Environment(\.unigrid) private var style
    let flags: [StopFlag]
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(flags) { flag in
                VStack(alignment: .leading, spacing: 3) {
                    Label(flag.title, systemImage: flag.symbol)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(isDanger(flag) ? style.seal : style.ink)
                        .lineLimit(expanded.contains(flag.id) ? nil : 2)
                    if let detail = flag.detail, expanded.contains(flag.id) {
                        Text(detail)
                            .font(UnigridStyle.caption)
                            .foregroundStyle(style.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if expanded.contains(flag.id) {
                        expanded.remove(flag.id)
                    } else {
                        expanded.insert(flag.id)
                    }
                }
                .accessibilityAddTraits(flag.detail == nil ? [] : .isButton)
                .accessibilityHint(flag.detail == nil ? "" : "Shows the details")
            }
        }
    }

    private func isDanger(_ flag: StopFlag) -> Bool {
        if case let .alert(_, _, danger) = flag {
            return danger
        }
        return false
    }
}

// MARK: - Days

/// The trip's dated days, with the driving into each and a warning on a long one.
struct TripDaysSection: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let days: [TripDay]

    var body: some View {
        if !days.isEmpty {
            Section {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("DAY")
                                .font(UnigridStyle.dataLabel)
                                .foregroundStyle(style.inkSecondary)
                            Text("\(index + 1)")
                                .font(UnigridStyle.figureSmall)
                                .foregroundStyle(style.ink)
                        }
                        .frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(UnigridStyle.rowTitle)
                                .foregroundStyle(style.ink)
                            Text(day.stopIDs.compactMap { store.place($0)?.name }
                                .joined(separator: " → "))
                                .font(UnigridStyle.rowDetail)
                                .foregroundStyle(style.inkSecondary)
                            if day.drivingSeconds > 0 {
                                Label(
                                    "\(UnigridsFormat.duration(day.drivingSeconds)) driving, "
                                        + UnigridsFormat.distance(metres: day.drivingMetres),
                                    systemImage: day.isLong
                                        ? "exclamationmark.triangle.fill" : "car"
                                )
                                .font(UnigridStyle.rowDetail)
                                .foregroundStyle(day.isLong ? style.seal : style.ink)
                            }
                            if day.isLong {
                                Text(
                                    "A long day at the wheel leaves little time for the parks. "
                                        + "Consider splitting it."
                                )
                                .font(UnigridStyle.caption)
                                .foregroundStyle(style.inkSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                SectionHead("Day by day", detail: "\(days.count)")
            }
        }
    }
}

// MARK: - Reminders
