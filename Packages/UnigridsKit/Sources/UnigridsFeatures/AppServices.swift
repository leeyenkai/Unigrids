import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference
import UserNotifications
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The app-wide services every window shares: live alerts, the transport network, the
/// brochure library and the undo prompt. One instance each, so the Mac's Settings window
/// and its main window see the same brochures and the same alerts.
@MainActor
public enum AppServices {
    public static let alerts = AlertsCenter()
    public static let transport = TransportStore()
    public static let brochures = BrochureLibrary()
    public static let undo = UndoCenter()
    public static let router = AppRouter()
    static let notifications = NotificationRouter()

    /// Make the app the notification centre's delegate. Called as the app starts, so a
    /// notification tapped to launch it reaches the router.
    public static func startRoutingNotifications() {
        UNUserNotificationCenter.current().delegate = notifications
    }

    /// Open a link outside the app, from code that has no view to ask.
    static func openExternally(_ url: URL) {
        #if os(iOS)
            UIApplication.shared.open(url)
        #else
            NSWorkspace.shared.open(url)
        #endif
    }
}

extension View {
    /// Put the shared services in a scene's environment.
    @MainActor
    public func unigridsServices() -> some View {
        environment(AppServices.alerts)
            .environment(AppServices.transport)
            .environment(AppServices.brochures)
            .environment(AppServices.undo)
            .environment(AppServices.detected)
            .environment(AppServices.router)
    }
}

/// The offer to put back what was just deleted (SPECIFICATION.md §9, "undo for
/// deletions"). One deletion at a time, for eight seconds.
@MainActor
@Observable
public final class UndoCenter {
    struct Offer: Identifiable {
        let id = UUID()
        let message: String
        let change: UndoableChange
    }

    private(set) var current: Offer?
    private var expiry: Task<Void, Never>?

    public init() {}

    func offer(_ change: UndoableChange, message: String) {
        let offer = Offer(message: message, change: change)
        current = offer
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.current?.id == offer.id else { return }
            self?.current = nil
        }
    }

    func undo(in context: ModelContext) {
        guard let offer = current else { return }
        current = nil
        try? LogStore(context: context).undo(offer.change)
    }

    func dismiss() {
        current = nil
    }
}

/// The undo prompt, along the bottom of the window.
struct UndoToast: View {
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style

    var body: some View {
        if let offer = undo?.current {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .foregroundStyle(style.bandInkSecondary)
                Text(offer.message)
                    .font(UnigridStyle.action)
                    .foregroundStyle(style.bandInk)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Undo") { undo?.undo(in: context) }
                    .buttonStyle(BrochureButtonStyle(.onBand, fullWidth: false))
                    .keyboardShortcut("z", modifiers: .command)
                Button {
                    undo?.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(style.bandInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(style.band)
            .frame(maxWidth: 560)
            .padding(.horizontal, 12)
            .padding(.bottom, 64)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}
