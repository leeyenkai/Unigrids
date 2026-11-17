import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The Settings switch for detection.
struct VisitDetectionToggle: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @AppStorage(DetectedVisits.enabledKey) private var enabled = false
    @Environment(DetectedVisits.self) private var detected: DetectedVisits?
    @State private var notice: String?

    var body: some View {
        #if os(iOS)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Suggest a visit when I arrive", isOn: Binding(
                    get: { enabled },
                    set: { isOn in
                        Task {
                            if isOn {
                                let granted = await VisitDetection.enable(store: store)
                                notice = granted ? nil
                                    : "Needs location access set to Always in Settings › Privacy."
                            } else {
                                await VisitDetection.disable()
                            }
                        }
                    }
                ))
                if let notice {
                    Text(notice)
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.seal)
                }
                if let detected, !detected.muted.isEmpty {
                    Button("Suggest again where I said not to (\(detected.muted.count))") {
                        detected.clearMuted()
                    }
                    .font(UnigridStyle.rowDetail)
                }
            }
        #else
            Text("Arrival suggestions are on iPhone and iPad, where the device travels with you.")
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
        #endif
    }
}
