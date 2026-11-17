import SwiftUI
import UnigridsCore

// The non-affiliation line every screen that needs one shares (SPECIFICATION.md §14).

/// The non-affiliation line, which the specification requires in onboarding and About
/// (§14, §15). Centralised so it reads identically wherever it appears.
public struct NonAffiliationNotice: View {
    @Environment(\.unigrid) private var style

    public init() {}

    public var body: some View {
        Text(
            "Unigrids is not affiliated with, endorsed by or sponsored by the "
                + "National Park Service, Japan's Ministry of the Environment, the Norwegian "
                + "Environment Agency, New Zealand's Department of Conservation or any other "
                + "government agency, and uses none of their marks."
        )
        .font(.footnote)
        .foregroundStyle(style.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
