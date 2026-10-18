import SwiftUI
import UnigridsCore

extension EnvironmentValues {
    /// The resolved Unigrid style for the reader's palette and the effective colour scheme.
    ///
    /// Injected once per scene by `unigridsAppearance()`. The default is the standard
    /// palette in dark, so a preview — or a host that forgot the modifier — renders the
    /// app's actual default rather than something that exists nowhere.
    @Entry public var unigrid: UnigridStyle = .fallback
}
