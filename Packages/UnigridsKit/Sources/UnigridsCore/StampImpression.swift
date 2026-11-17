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
    /// The calendar the stamp's day is reckoned in: the place's own zone.
    public let calendar: Calendar
    /// Whose passport book the stamp is in, which fixes its face (ADR 0013).
    public let country: Country
    /// The place's name in its own script, set large on a Japanese face: 知床国立公園.
    public let localName: String?
    /// The picture in the face's centre band: the park's own drawing or its kind's motif.
    public let emblem: Emblem?

    /// `country` decides the America 250 seal, which only a US stamp carries; it has no
    /// default so no caller can forget it.
    public init(
        siteName: String,
        date: Date,
        stateCode: String,
        region: PassportRegion,
        country: Country,
        seed: UInt64,
        isVerifiedOnSite: Bool = false,
        calendar: Calendar = UnigridsCalendar.gregorian(),
        localName: String? = nil,
        emblem: Emblem? = nil
    ) {
        self.siteName = siteName
        self.date = date
        self.stateCode = stateCode
        self.region = region
        impression = StampImpression(seed: seed)
        hasAmerica250Seal = America250.applies(to: date, in: country, calendar: calendar)
        self.isVerifiedOnSite = isVerifiedOnSite
        self.calendar = calendar
        self.country = country
        self.localName = localName
        self.emblem = emblem
    }

    /// The date as the book's cancellations print it — `18 OCT 2026` in the US and
    /// Australian books, `2026.10.18` in Japan's, `18.10.2026` in Norway's and New
    /// Zealand's, `2026-10-18` in Canada's — in the calendar the seal was
    /// decided in, so the face and the overprint can never disagree about the year.
    public func dateLine() -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = parts.day, let month = parts.month, let year = parts.year else {
            return ""
        }
        switch country {
        case .japan: return String(format: "%d.%02d.%02d", year, month, day)
        case .norway, .newZealand: return String(format: "%02d.%02d.%d", day, month, year)
        // Canada's bilingual cancellations print the date as numbers, year first.
        case .canada: return String(format: "%d-%02d-%02d", year, month, day)
        case .unitedStates, .australia: break
        }
        let months = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ]
        let monthName = months.indices.contains(month - 1) ? months[month - 1] : ""
        return String(format: "%02d %@ %d", day, monthName, year)
    }
}
