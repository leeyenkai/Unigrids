import SwiftUI
import UnigridsCore

extension View {
    /// Reads the reader's appearance and palette choice and resolves the Unigrid style for
    /// everything below.
    ///
    /// Apply once per scene root. Both the main window and the macOS Settings scene need
    /// it, and because the choice lives in `UserDefaults` rather than in an object one of
    /// them owns, the two always agree without anything being passed between them.
    public func unigridsAppearance() -> some View {
        modifier(UnigridsAppearance())
    }
}

private struct UnigridsAppearance: ViewModifier {
    @AppStorage(AppearanceDefaults.appearance)
    private var appearance = AppearancePreference.standard
    @AppStorage(AppearanceDefaults.palette)
    private var palette = Palette.standard

    func body(content: Content) -> some View {
        content
            .modifier(ResolveUnigridStyle(palette: palette))
            .preferredColorScheme(appearance.preferredColorScheme)
    }
}

/// Resolves inside the forced scheme rather than alongside it.
///
/// `preferredColorScheme` travels up to the window as a preference and is then applied
/// back down the whole tree. Reading `\.colorScheme` in the same `body` that sets it would
/// see the previous value on the first pass and flash the wrong palette; nesting means
/// this view's scheme is already the effective one — forced when the reader picked Light
/// or Dark, the system's when they picked Automatic.
private struct ResolveUnigridStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    let palette: Palette

    func body(content: Content) -> some View {
        let style = UnigridStyle(palette: palette, scheme: PaletteScheme(scheme))
        content
            .environment(\.unigrid, style)
            .tint(style.accent)
    }
}

extension AppearancePreference {
    /// `nil` means "whatever the system says", which is what Automatic is.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}
