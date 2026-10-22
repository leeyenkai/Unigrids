import Foundation

/// Measurement formatting the whole app shares, so a park's area reads the same on the
/// map card, in the guide and in the stats.
///
/// US locales see acres and feet; everyone else sees hectares and metres.
public enum UnigridsFormat {
    /// Whether to print US customary units.
    ///
    /// Testing `== .metric` would be wrong: `Locale.MeasurementSystem` has three cases,
    /// and the UK reports `.uk`. That sent every British reader down the imperial path
    /// and printed park elevations in feet.
    public static func usesUSUnits(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us
    }

    /// `147,237 acres` or `59,585 ha`, following the locale.
    ///
    /// Whole units only. Converting acres to hectares otherwise produces a figure like
    /// `19,859.947893 ha`, which reads as a precision the source never had.
    public static func area(acres: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: acres, unit: UnitArea.acres)
        let converted = usesUSUnits(locale)
            ? measurement
            : measurement.converted(to: .hectares)
        return converted.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            .locale(locale)
        )
    }

    /// `1,128–2,660 m`, or a single figure when only one end is known.
    public static func elevationRange(
        lowest: Double?,
        highest: Double?,
        locale: Locale = .current
    ) -> String? {
        switch (lowest, highest) {
        case let (low?, high?) where low < high:
            "\(elevation(low, locale: locale, bare: true))–\(elevation(high, locale: locale))"
        case let (low?, nil):
            elevation(low, locale: locale)
        case let (nil, high?):
            elevation(high, locale: locale)
        case let (low?, high?):
            elevation(max(low, high), locale: locale)
        default:
            nil
        }
    }

    /// `2,660 m` or `8,726 ft`. `bare` drops the unit, for the low end of a range.
    public static func elevation(
        _ metres: Double,
        locale: Locale = .current,
        bare: Bool = false
    ) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
        let converted = usesUSUnits(locale)
            ? measurement.converted(to: .feet)
            : measurement
        if bare {
            return converted.value.formatted(
                .number.precision(.fractionLength(0)).locale(locale)
            )
        }
        return converted.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            .locale(locale)
        )
    }

    /// `8.7 km` or `5.4 mi`, for trail lengths and distances to a park.
    public static func distance(metres: Double, locale: Locale = .current) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(width: .abbreviated, usage: .road)
                    .locale(locale)
            )
    }

    /// `31°C` or `88°F`, by the reader's measurement system.
    public static func temperature(celsius: Double, locale: Locale = .current) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let converted = usesUSUnits(locale) ? measurement.converted(to: .fahrenheit) : measurement
        return converted.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            .locale(locale)
        )
    }

    /// `3 h 20 min`, for trail estimates.
    public static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated)
        )
    }

    /// `4.6 million` for visitation figures, which read badly at full precision.
    public static func visitors(_ count: Int, locale: Locale = .current) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000
            let formatted = millions.formatted(
                .number.precision(.fractionLength(millions < 10 ? 1 : 0)).locale(locale)
            )
            return "\(formatted) million"
        }
        return count.formatted(.number.locale(locale))
    }

    /// Elevation gain expressed in Everests, the stat the specification asks for (§11).
    ///
    /// Measured from sea level to the summit, 8,848 m, which is the figure the comparison
    /// is colloquially made against.
    public static let everestMetres: Double = 8848

    public static func everests(gainMetres: Double, locale: Locale = .current) -> String {
        let count = gainMetres / everestMetres
        let precision = count < 10 ? 2 : 1
        return count.formatted(
            .number.precision(.fractionLength(precision)).locale(locale)
        )
    }
}

// MARK: - Dates

/// The four ways the app writes a date, so the same day reads the same everywhere.
///
/// Each takes the calendar the date is reckoned in — the place's own, for anything that
/// happened somewhere — so a visit's day does not move with the device's time zone.
public typealias DateStyle = Date.FormatStyle

extension UnigridsFormat {
    /// "12 Jun 2026": a visit, a stamp, a trip's dates.
    public static func day(in calendar: Calendar = .unigrids) -> DateStyle {
        styled(.dateTime.day().month(.abbreviated).year(), calendar)
    }

    /// "Wed 12 Jun": a day of a trip, a forecast.
    public static func weekday(in calendar: Calendar = .unigrids) -> DateStyle {
        styled(.dateTime.weekday(.abbreviated).day().month(.abbreviated), calendar)
    }

    /// "June 2026": first and latest visit, a month of photographs.
    public static func month(in calendar: Calendar = .unigrids) -> DateStyle {
        styled(.dateTime.month(.wide).year(), calendar)
    }

    /// "12 Jun 2026, 10:42": a reminder, when alerts were fetched.
    public static func moment(in calendar: Calendar = .unigrids) -> DateStyle {
        styled(.dateTime.day().month(.abbreviated).year().hour().minute(), calendar)
    }

    private static func styled(_ style: DateStyle, _ calendar: Calendar) -> DateStyle {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}

extension Calendar {
    /// `UnigridsCalendar.gregorian()`: Gregorian, in the device's zone.
    public static var unigrids: Calendar {
        UnigridsCalendar.gregorian()
    }
}
