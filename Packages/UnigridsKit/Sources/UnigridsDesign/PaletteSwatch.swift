import SwiftUI
import UnigridsCore

/// A palette shown as what it actually is: paper, a band, and an accent rule.
///
/// Resolved in the scheme the reader is currently in, so the swatch previews what they
/// will get rather than an idealised light-mode version of it.
public struct PaletteSwatch: View {
    @Environment(\.colorScheme) private var scheme

    private let palette: Palette
    private let size: CGFloat

    public init(palette: Palette, size: CGFloat = 26) {
        self.palette = palette
        self.size = size
    }

    public var body: some View {
        let colors = palette.colors(PaletteScheme(scheme))
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(colors.band))
                .frame(height: size * 0.3)
            Rectangle()
                .fill(Color(colors.page))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(colors.accent))
                        .frame(width: size * 0.42, height: 2)
                        .padding(.leading, size * 0.16)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
