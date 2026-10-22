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

/// The offer to take back what was just changed (SPECIFICATION.md §9, "undo for
/// deletions"). One change at a time, for eight seconds.
///
/// Every presentation root — the window, each sheet, a Mac place window — is a host
/// (`undoHost()`). An offer shows in the host it was made from, or, once that host has
/// closed, in the nearest one beneath it: a visit deleted from its editor, which then
/// closes, offers its undo on the screen underneath; an impression deleted in the
/// impressions sheet, which stays open, offers it there.
@MainActor
@Observable
public final class UndoCenter {
    struct Offer: Identifiable {
        let id = UUID()
        let message: String
        let change: UndoableChange
        /// The hosts open when the offer was made, root first, ending at its origin.
        let chain: [UUID]
    }

    private(set) var current: Offer?
    private(set) var hosts: [UUID] = []
    private(set) var failure: String?
    private var expiry: Task<Void, Never>?

    public init() {}

    func register(_ host: UUID) {
        hosts.removeAll { $0 == host }
        hosts.append(host)
    }

    func unregister(_ host: UUID) {
        hosts.removeAll { $0 == host }
    }

    /// The host the current offer shows in.
    var displayHost: UUID? {
        current?.chain.last { hosts.contains($0) }
    }

    func offer(_ change: UndoableChange, message: String, from host: UUID? = nil) {
        let origin = host.flatMap { hosts.firstIndex(of: $0) } ?? (hosts.count - 1)
        let chain = origin >= 0 ? Array(hosts[...origin]) : []
        let offer = Offer(message: message, change: change, chain: chain)
        current = offer
        failure = nil
        AccessibilityNotification.Announcement(message).post()
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
        do {
            try LogStore(context: context).undo(offer.change)
            // A deletion that took reminders put them back; their notifications come back
            // too. A creation that is undone has no reminders to lose.
            Task { await ReminderScheduler.reconcile(Self.reminders(in: context)) }
        } catch {
            failure = "That could not be undone: \(error.localizedDescription)"
            AccessibilityNotification.Announcement(failure ?? "").post()
        }
    }

    func dismiss() {
        current = nil
        failure = nil
    }

    private static func reminders(in context: ModelContext) -> [Reminder] {
        (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
    }
}

extension EnvironmentValues {
    /// The undo host a view sits in, for offers made from it.
    @Entry var undoHost: UUID?
}

extension View {
    /// Make this view a place the undo prompt can show: the root of a window or a sheet.
    public func undoHost() -> some View {
        modifier(UndoHost())
    }

    /// A sheet that is an undo host and has the app's services, whatever presents it. Use
    /// this rather than `.sheet` (SwiftLint holds the line), so an undo offered inside a
    /// sheet is never drawn behind it.
    func unigridsSheet(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        sheet(isPresented: isPresented) { content().unigridsServices().undoHost() }
    }

    func unigridsSheet<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        sheet(item: item) { content($0).unigridsServices().undoHost() }
    }
}

private struct UndoHost: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.undoHost, id)
            .overlay(alignment: .bottom) {
                UndoToast(host: id)
            }
            .onAppear { AppServices.undo.register(id) }
            .onDisappear { AppServices.undo.unregister(id) }
    }
}

/// The undo prompt, along the bottom of its host.
struct UndoToast: View {
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    let host: UUID

    var body: some View {
        Group {
            if let undo, undo.displayHost == host, let offer = undo.current {
                bar(message: offer.message, canUndo: true)
            } else if let undo, let failure = undo.failure, undo.hosts.last == host {
                bar(message: failure, canUndo: false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: undo?.current?.id)
    }

    private func bar(message: String, canUndo: Bool) -> some View {
        HStack(spacing: 14) {
            Image(canUndo ? UnigridsSymbol.delete : UnigridsSymbol.warning)
                .foregroundStyle(style.bandInkSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(UnigridStyle.action)
                .foregroundStyle(style.bandInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            if canUndo {
                Button("Undo") { undo?.undo(in: context) }
                    .buttonStyle(BrochureButtonStyle(.onBand, fullWidth: false))
            }
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
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
