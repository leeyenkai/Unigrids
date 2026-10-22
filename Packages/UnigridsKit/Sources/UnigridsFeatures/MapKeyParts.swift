import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// The map key's samples and its reading guide (SPECIFICATION.md §5).

/// A short length of road or rail, drawn as the map draws it.
struct TransportSample: View {
    @Environment(\.unigrid) private var style
    let layer: TransportLayer

    var body: some View {
        let ink = AtlasInk(scheme: style.scheme, palette: style.palette)
        let look = ink.transportStyle(layer)
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            if let casing = look.casing, look.casingWidth > 0 {
                context.stroke(
                    path, with: .color(Color(casing)),
                    style: StrokeStyle(lineWidth: look.casingWidth, lineCap: .round)
                )
            }
            context.stroke(
                path, with: .color(Color(look.line)),
                style: StrokeStyle(lineWidth: look.width, lineCap: .round)
            )
            if let centre = look.centre, look.centreWidth > 0 {
                context.stroke(
                    path, with: .color(Color(centre)),
                    style: StrokeStyle(lineWidth: look.centreWidth, dash: look.centreDash)
                )
            }
        }
        .background(style.scheme == .dark ? Color.black.opacity(0.4) : Color.gray.opacity(0.15))
        .accessibilityHidden(true)
    }
}

/// How to read a pin: what its colour, shape and marks mean, and what the areas and
/// numbered circles are.
struct LegendKey: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Colour and symbol: the kind of place")
            Text(
                "Every kind of place above has its own symbol. Related kinds share a colour: "
                    + "history is brown, water blue, forests and preserves green."
            )
            .font(UnigridStyle.rowDetail)
            .foregroundStyle(style.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Hairline()
            Kicker("Shape: who runs it")
            row(SitePin(type: .nationalPark), "Large black square: a national park")
            row(SitePin(type: .historicSite), "Square: another National Park Service site")
            row(SitePin(type: .statePark), "Circle: a state park")
            row(
                SitePin(type: .nationalForest),
                "Hexagon: other public land — national forests, wildlife refuges, BLM land — "
                    + "and natural landmarks and byways"
            )

            Hairline()
            Kicker("Marks on a pin")
            row(SitePin(type: .nationalPark, status: .visited), "Green tick: you have been")
            row(
                SitePin(type: .nationalPark, status: .planned),
                "Dashed ring: on a trip you are planning"
            )
            row(AlertSample(), "Red corner: a danger alert is posted; a plain one, a closure")

            Hairline()
            Kicker("Areas and groups")
            row(AreaSample(), "Tinted area: the place's boundary, in its colour")
            row(ClusterSample(), "Black circle: places grouped together; zoom in to see them")
            row(
                ParkClusterSample(),
                "Starred square: national parks grouped when the whole country is in view"
            )
        }
        .padding(.vertical, 4)
    }

    private func row(_ sample: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            sample
                .frame(width: 36)
            Text(text)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A national park's pin with a danger badge, as the map draws one.
private struct AlertSample: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        SitePin(type: .nationalPark)
            .overlay(alignment: .topTrailing) {
                Rectangle()
                    .fill(style.seal)
                    .overlay { Rectangle().strokeBorder(Color(SiteInk.pictogram), lineWidth: 1) }
                    .frame(width: 9, height: 9)
                    .offset(x: -0.5, y: 0.5)
            }
    }
}

/// A patch of outline, tinted as the map tints a forest.
private struct AreaSample: View {
    var body: some View {
        let tint = Color(SiteInk.wildland.pin)
        Rectangle()
            .fill(tint.opacity(0.22))
            .overlay { Rectangle().strokeBorder(tint, lineWidth: 1.5) }
            .frame(width: 26, height: 18)
            .accessibilityHidden(true)
    }
}

/// A cluster's circle, as the map draws one.
private struct ClusterSample: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        Text("12")
            .font(.custom("HelveticaNeue-Bold", size: 10, relativeTo: .caption2))
            .foregroundStyle(style.bandInk)
            .frame(width: 24, height: 24)
            .background(Circle().fill(style.band))
            .overlay { Circle().strokeBorder(Color(SiteInk.pictogram), lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

/// National parks gathered at country scale, as the map draws them.
private struct ParkClusterSample: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: UnigridsSymbol.site(.nationalPark))
                .font(.system(size: 9, weight: .semibold))
            Text("5")
                .font(.custom("HelveticaNeue-Bold", size: 10, relativeTo: .caption2))
        }
        .foregroundStyle(Color(SiteInk.pictogram))
        .padding(.horizontal, 5)
        .frame(height: 20)
        .background(Color(SiteInk.nationalPark.pin))
        .overlay { Rectangle().strokeBorder(Color(SiteInk.pictogram), lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}
