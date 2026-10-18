import Foundation

/// How one stamp impression sits on the page.
///
/// The specification (§9) asks for a slight tilt, offset and ink density per impression,
/// "fixed by a stored seed so it looks the same every time". That is the whole contract
/// here: the seed is persisted with the stamp, and everything visual derives from it. A
/// stamp drawn today, after a relaunch, and after an iCloud sync to another device all
/// land in the same place.
public struct StampImpression: Hashable, Sendable {
    /// Rotation in degrees, roughly ±6°, the way a hand-held stamp lands.
    public let tiltDegrees: Double
    /// Horizontal nudge from the slot's centre, in points.
    public let offsetX: Double
    /// Vertical nudge from the slot's centre, in points.
    public let offsetY: Double
    /// Ink coverage from 0 to 1 — a tired pad prints lighter.
    public let inkDensity: Double
    /// Rotation of the America 250 overprint, independent of the impression beneath it.
    public let sealTiltDegrees: Double

    /// Derive an impression from its stored seed.
    public init(seed: UInt64) {
        var random = DeterministicRandom(seed: seed)
        tiltDegrees = random.double(in: -6 ... 6)
        offsetX = random.double(in: -5 ... 5)
        offsetY = random.double(in: -4 ... 4)
        inkDensity = random.double(in: 0.78 ... 1.0)
        sealTiltDegrees = random.double(in: -14 ... 14)
    }

    /// A fresh seed for a new stamp. Stored on the stamp record, never recomputed.
    public static func newSeed() -> UInt64 {
        UInt64.random(in: UInt64.min ... UInt64.max)
    }
}

/// The face of a passport cancellation (SPECIFICATION.md §9).
///
/// Cancellation style: site name across the top, the date through the centre, the state at
/// the bottom, in the region's ink.
public struct StampFace: Hashable, Sendable {
    public let siteName: String
    public let date: Date
    public let stateCode: String
    public let region: PassportRegion
    public let impression: StampImpression
    /// Whether the America 250 seal overprints this impression.
    public let hasAmerica250Seal: Bool
    /// Set when the stamp was made on site, confirmed by location.
    public let isVerifiedOnSite: Bool

    public init(
        siteName: String,
        date: Date,
        stateCode: String,
        region: PassportRegion,
        seed: UInt64,
        isVerifiedOnSite: Bool = false,
        calendar: Calendar = .current
    ) {
        self.siteName = siteName
        self.date = date
        self.stateCode = stateCode
        self.region = region
        impression = StampImpression(seed: seed)
        hasAmerica250Seal = America250.applies(to: date, calendar: calendar)
        self.isVerifiedOnSite = isVerifiedOnSite
    }

    /// The date as a cancellation prints it: `18 OCT 2026`.
    public func dateLine(locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = parts.day, let month = parts.month, let year = parts.year else {
            return ""
        }
        let months = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ]
        let monthName = months.indices.contains(month - 1) ? months[month - 1] : ""
        return String(format: "%02d %@ %d", day, monthName, year)
    }
}
