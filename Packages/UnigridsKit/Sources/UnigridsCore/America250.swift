import Foundation

/// The America 250 overprint rule (SPECIFICATION.md §9).
///
/// Every stamp dated in calendar year 2026 — the 250th anniversary year of 1776 — carries
/// a red `AMERICA 250` seal across the corner of the regular impression. The rule follows
/// the **stamp's date**, not when the user entered it, so a 2026 visit logged in 2028
/// still earns the seal, and a back-dated 2025 visit entered during 2026 does not.
public enum America250 {
    /// The commemorative year.
    public static let year = 2026

    /// Whether a stamp dated `date` carries the seal.
    ///
    /// The comparison uses the calendar the stamp was made in, so a date near midnight on
    /// New Year's Eve resolves the way the user's own calendar shows it.
    public static func applies(to date: Date, calendar: Calendar = UnigridsCalendar.gregorian()) -> Bool {
        calendar.component(.year, from: date) == year
    }

    /// The text on the seal.
    public static let sealText = "AMERICA 250"
}
