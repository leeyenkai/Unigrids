import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The app-wide services every window shares: live alerts, the transport network, the
/// brochure library and the undo prompt. One instance each, so the Mac's Settings window
/// and its main window see the same brochures and the same alerts.
@MainActor
public enum AppServices {
    public static let alerts = AlertsCenter()
    public static let transport = TransportStore()
    public static let brochures = BrochureLibrary()
    public static let undo = UndoCenter()
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
        let record: DeletedRecord
    }

    private(set) var current: Offer?
    private var expiry: Task<Void, Never>?

    public init() {}

    func offer(_ record: DeletedRecord, message: String) {
        let offer = Offer(message: message, record: record)
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
        try? LogStore(context: context).restore(offer.record)
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
