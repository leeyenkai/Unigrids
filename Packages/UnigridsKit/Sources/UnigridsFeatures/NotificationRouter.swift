import Foundation
import Observation
import UserNotifications

/// What a notification is about, written into its `userInfo` under `key` so a tap can
/// be routed without guessing from its text.
enum NotificationRoute: String {
    case arrival
    case reminder
    case alert

    static let key = "route"
}

/// Somewhere in the app a notification, or anything else outside a screen, wants the
/// reader taken.
public enum AppRoute: Sendable, Equatable {
    /// A detected arrival: the Trips tab, with the log sheet for it open.
    case arrival(placeID: String, date: Date)
    /// A trip's page.
    case trip(UUID)
    /// A place's page, scrolled to nothing in particular: where a park's alerts are.
    case place(String)
}

/// The route the app owes the reader, until a window takes it.
///
/// Every window sees the same router, and the one the reader is looking at consumes the
/// route, so a tap opens one window's screen rather than every window's.
@MainActor
@Observable
public final class AppRouter {
    public var pending: AppRoute?

    public init() {}

    /// The pending route, once: it is cleared as it is read.
    public func take() -> AppRoute? {
        defer { pending = nil }
        return pending
    }
}

/// The notification centre's delegate: banners while the app is open, and a tap turned
/// into an `AppRoute`.
///
/// Made the delegate as the app starts, so a tap that launches the app is not lost, and
/// held by `AppServices` because the centre keeps its delegate only weakly. The
/// callbacks arrive off the main actor; only plain values cross to it.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // No stored state: the router reads the notification and hands a value to the main
    // actor, so sharing it across threads is safe.

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
            -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let route = Self.route(from: info)
        let link = (info["url"] as? String).flatMap(URL.init(string:))
        completionHandler()
        Task { @MainActor in
            if let route {
                AppServices.router.pending = route
            }
            if let link {
                AppServices.openExternally(link)
            }
        }
    }

    static func route(from info: [AnyHashable: Any]) -> AppRoute? {
        switch (info[NotificationRoute.key] as? String).flatMap(NotificationRoute.init) {
        case .arrival:
            guard let place = info["place"] as? String,
                  let seconds = info["date"] as? TimeInterval
            else { return nil }
            return .arrival(placeID: place, date: Date(timeIntervalSince1970: seconds))
        case .reminder:
            return (info["trip"] as? String).flatMap(UUID.init(uuidString:)).map(AppRoute.trip)
        case .alert:
            return (info["place"] as? String).map(AppRoute.place)
        case nil:
            return nil
        }
    }
}
