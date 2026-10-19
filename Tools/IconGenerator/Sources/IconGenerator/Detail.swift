/// How much of the mark a given pixel size can carry.
///
/// Every size is drawn at its true pixel count rather than downscaled from one master,
/// so detail is dropped as the canvas shrinks instead of turning to mush. A gutter that
/// lands on two thirds of a pixel is not a gutter, it is a grey smear.
enum Detail {
    /// 16 and 32 px. Two covers, two ridges, and the band. Nothing printed on the cover
    /// survives: at this size a caption rule is one pixel of noise along an edge.
    case small
    /// 64 px and up. The whole stack, three ridges, and the cover's two marks.
    case full

    static func forPixels(_ pixels: Int) -> Detail {
        pixels < 128 ? .small : .full
    }

    var drawsEveryBlock: Bool {
        self == .full
    }

    /// Type goes on only where it could be read. Below 128 px a park's name is a smear
    /// along the band, which is worse than no name at all.
    var setsType: Bool {
        self == .full
    }
}
