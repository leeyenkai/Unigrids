import SwiftUI

/// What a sheet offers in its toolbar, in the places each platform expects them.
public enum SheetActions {
    /// A sheet that only shows something: Done, at the trailing edge.
    case done(() -> Void)
    /// A sheet that changes something: Cancel leading, the action trailing and in bold.
    case confirm(_ title: String, enabled: Bool = true, cancel: () -> Void, action: () -> Void)
}

/// The page every sheet is printed on (docs/design-system.md §2): the band with the
/// sheet's title reversed out of it, the palette's paper behind the content, its actions
/// in the toolbar where the platform puts them, and a size on the Mac, where a sheet
/// built on a list otherwise collapses.
///
/// The navigation bar stays the platform's own and carries only the actions; the band
/// carries the title, so it is never said twice.
public struct SheetPage<Content: View>: View {
    private let title: String
    private let kicker: String?
    private let actions: SheetActions
    private let width: CGFloat
    private let height: CGFloat
    private let content: Content

    public init(
        _ title: String,
        kicker: String? = nil,
        actions: SheetActions,
        width: CGFloat = 480,
        height: CGFloat = 620,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.kicker = kicker
        self.actions = actions
        self.width = width
        self.height = height
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            content
                .paperPage()
                .safeAreaInset(edge: .top, spacing: 0) {
                    BandHeader(title, kicker: kicker, compact: true)
                }
                .toolbarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .sheetSize(width: width, height: height)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch actions {
        case let .done(done):
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: done)
            }
        case let .confirm(title, enabled, cancel, action):
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(title, action: action)
                    .disabled(!enabled)
            }
        }
    }
}
