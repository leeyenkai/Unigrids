import Foundation

/// Regenerates `App/Unigrids/Assets.xcassets/AppIcon.appiconset`.
///
/// Run it with no arguments from `Tools/IconGenerator`; pass a directory to write
/// somewhere else.
var arguments = Array(CommandLine.arguments.dropFirst())

/// `--park zion|yosemite` picks which park stands up out of the stack.
///
/// Zion is the default because it is what ships: running with no arguments has to
/// reproduce the committed PNGs exactly, or the generator stops being the source of
/// truth for them.
var scene = Scene.zion
if let flag = arguments.firstIndex(of: "--park"), flag + 1 < arguments.count {
    switch arguments[flag + 1] {
    case "yosemite": scene = .yosemite
    default: scene = .zion
    }
    arguments.removeSubrange(flag ... (flag + 1))
}

/// `--preview` writes a few sizes to look at without touching the asset catalogue.
let isPreview = arguments.contains("--preview")
arguments.removeAll { $0 == "--preview" }

let output: URL = if let first = arguments.first {
    .init(fileURLWithPath: first)
} else {
    .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // IconGenerator
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // Tools/IconGenerator
        .deletingLastPathComponent() // Tools
        .deletingLastPathComponent() // the repository root
        .appending(path: "App/Unigrids/Assets.xcassets/AppIcon.appiconset")
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Clear the generated PNGs first, so a renamed entry cannot leave a stale file behind
/// for `actool` to find.
let existing = try FileManager.default.contentsOfDirectory(atPath: output.path())
for name in existing where name.hasSuffix(".png") {
    try FileManager.default.removeItem(at: output.appending(path: name))
}

let entries = isPreview
    ? AssetCatalog.entries.filter { [16, 32, 64, 128, 1024].contains($0.pixels) }
    : AssetCatalog.entries

for entry in entries {
    let renderer = IconRenderer(
        pixels: entry.pixels,
        palette: entry.variant.palette,
        detail: Detail.forPixels(entry.pixels),
        scene: scene,
        variant: entry.variant
    )
    guard let image = renderer.image() else {
        throw GeneratorError.renderFailed(entry.pixels)
    }
    try PNG.write(image, to: output.appending(path: entry.filename))
    print("  \(entry.filename)  \(entry.pixels)x\(entry.pixels)")
}

if !isPreview {
    try AssetCatalog.contentsJSON()
        .write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    print("  Contents.json")
}

print("Wrote \(entries.count) images to \(output.path())")
