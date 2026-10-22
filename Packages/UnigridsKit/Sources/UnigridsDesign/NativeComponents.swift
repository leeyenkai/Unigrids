import SwiftUI
import UnigridsCore

// How a place is drawn wherever it appears outside a guide (SPECIFICATION.md §14,
// docs/adr/0009), and the non-affiliation line every screen that needs one shares.

/// How a place is drawn on the map: colour by kind of place, symbol by kind.
public enum PlaceStyle {
    /// Takes the resolved style because a site ink has a light and a dark variant: the
    /// light ones sit at under 2:1 on a dark list row, which is how they went unread.
    public static func tint(for place: Place, in style: UnigridStyle) -> Color {
        style.siteTint(for: place)
    }

    public static func symbol(for place: Place) -> String {
        UnigridsSymbol.place(place.kind)
    }
}

/// The non-affiliation line, which the specification requires in onboarding and About
/// (§14, §15). Centralised so it reads identically wherever it appears.
public struct NonAffiliationNotice: View {
    @Environment(\.unigrid) private var style

    public init() {}

    public var body: some View {
        Text(
            "Unigrids is not affiliated with, endorsed by or sponsored by the "
                + "National Park Service or any other government agency."
        )
        .font(.footnote)
        .foregroundStyle(style.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
