#if canImport(UIKit)
    import UIKit
#endif
import SwiftUI
import UnigridsCore

/// Picks which park's icon the app wears.
///
/// Alternate app icons are a UIKit feature, and macOS has no equivalent of
/// `setAlternateIconName`. So the choice is offered on iPhone and iPad, and on the Mac
/// the row says so instead — a picker there would be a control that does nothing, and
/// the first version shipped exactly that.
struct AppIconPicker: View {
    #if canImport(UIKit)
        @AppStorage(AppearanceDefaults.appIcon)
        private var choice = AppIconChoice.standard

        @State private var failure: String?
    #endif

    var body: some View {
        #if canImport(UIKit)
            Picker("App icon", selection: $choice) {
                ForEach(AppIconChoice.allCases) { icon in
                    Text("\(icon.name) · \(icon.state)").tag(icon)
                }
            }
            .onChange(of: choice) { _, picked in
                apply(picked)
            }
            .onAppear {
                // UIKit is the source of truth: the reader may have changed the icon, or
                // a reinstall may have reset it, without `UserDefaults` hearing about it.
                choice = AppIconChoice.named(UIApplication.shared.alternateIconName)
            }

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        #else
            Text(
                "The park icons are for iPhone and iPad. On the Mac, Unigrids keeps its "
                    + "standard icon."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    #if canImport(UIKit)
        private func apply(_ picked: AppIconChoice) {
            guard UIApplication.shared.supportsAlternateIcons else {
                failure = "This device does not support changing the app icon."
                return
            }
            UIApplication.shared.setAlternateIconName(picked.alternateIconName) { error in
                Task { @MainActor in
                    guard let error else {
                        failure = nil
                        return
                    }
                    // Put the picker back where it was: the icon did not change, and a
                    // row that claims otherwise is worse than no row.
                    choice = AppIconChoice.named(UIApplication.shared.alternateIconName)
                    failure = "The icon could not be changed: \(error.localizedDescription)"
                }
            }
        }
    #endif
}
