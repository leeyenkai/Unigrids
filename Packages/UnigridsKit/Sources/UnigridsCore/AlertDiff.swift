import Foundation

/// Which live park alerts are worth a notification (SPECIFICATION.md §10, "a notification
/// when a new danger or closure alert appears"): a danger or a closure, at a park on a trip
/// coming up, the first time it is seen.
///
/// A park the watch has not looked at before is taken in silently — adding Yellowstone to
/// a trip should not bring five notifications about closures posted weeks ago, which the
/// trip's page already shows. From the next look on, what is new is news.
public enum AlertDiff {
    public struct Alert: Hashable, Sendable {
        public let id: String
        /// The NPS park code, lower case.
        public let parkCode: String
        /// A danger or a closure, rather than a caution or information.
        public let isUrgent: Bool

        public init(id: String, parkCode: String, isUrgent: Bool) {
            self.id = id
            self.parkCode = parkCode.lowercased()
            self.isUrgent = isUrgent
        }
    }

    /// What the watch has seen: the parks it looked at, and the alerts posted there.
    public struct Seen: Codable, Equatable, Sendable {
        public var parks: Set<String>
        public var alerts: Set<String>

        public init(parks: Set<String> = [], alerts: Set<String> = []) {
            self.parks = parks
            self.alerts = alerts
        }
    }

    /// The alerts to tell the reader about, and what has now been seen. `watching` is the
    /// set of park codes the fetch covered.
    public static func check(
        _ alerts: [Alert],
        watching: Set<String>,
        seen: Seen
    ) -> (notify: [Alert], seen: Seen) {
        let watching = Set(watching.map { $0.lowercased() })
        let notify = alerts.filter {
            $0.isUrgent && seen.parks.contains($0.parkCode) && !seen.alerts.contains($0.id)
        }
        // Only what is posted now is remembered, so the list never grows past the live feed.
        let now = Seen(parks: watching, alerts: Set(alerts.map(\.id)))
        return (notify, now)
    }
}
