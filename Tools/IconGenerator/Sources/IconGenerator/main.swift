import Foundation

/// Regenerates `App/Unigrids/Assets.xcassets/AppIcon.appiconset`.
///
/// Run it with no arguments from `Tools/IconGenerator`; pass a directory to write
/// somewhere else.
var arguments = Array(CommandLine.arguments.dropFirst())

/// `--park <name>` picks which park the icon is for: its land behind the stack and its
/// brochure on top. Names are the `Scene` raw values — zion, grandCanyon, yosemite,
/// sequoia, rockyMountain, olympic, acadia, joshuaTree, everglades, congaree.
///
/// Zion is the default because it is what ships as the app's own icon: running with no
/// arguments has to reproduce the committed PNGs exactly, or the generator stops being
/// the source of truth for them.
var scene = Scene.standard
if let flag = arguments.firstIndex(of: "--park"), flag + 1 < arguments.count {
    guard let named = Scene(rawValue: arguments[flag + 1]) else {
        throw GeneratorError.unknownPark(arguments[flag + 1])
    }
    scene = named
    arguments.removeSubrange(flag ... (flag + 1))
}

/// `--all` writes the shipping icon and every alternate, each into its own appiconset.
let isEveryPark = arguments.contains("--all")
arguments.removeAll { $0 == "--all" }

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

/// One appiconset: the images, and the `Contents.json` that indexes them.
func write(
    park: Scene,
    entries: [CatalogEntry],
    to directory: URL,
    writeContents: Bool
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // Clear the generated PNGs first, so a renamed entry cannot leave a stale file
    // behind for `actool` to find.
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path())
        where name.hasSuffix(".png")
    {
        try FileManager.default.removeItem(at: directory.appending(path: name))
    }

    for entry in entries {
        let renderer = IconRenderer(
            pixels: entry.pixels,
            palette: entry.variant.palette,
            detail: Detail.forPixels(entry.pixels),
            scene: park,
            variant: entry.variant
        )
        guard let image = renderer.image() else {
            throw GeneratorError.renderFailed(entry.pixels)
        }
        try PNG.write(image, to: directory.appending(path: entry.filename))
    }

    if writeContents {
        try AssetCatalog.contentsJSON(for: entries)
            .write(
                to: directory.appending(path: "Contents.json"),
                atomically: true,
                encoding: .utf8
            )
    }
    print("  \(directory.lastPathComponent)  \(entries.count) images")
}

if isEveryPark {
    // The shipping icon, then one appiconset per alternate. The names match the
    // `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` build setting, which is what
    // `setAlternateIconName` asks for at runtime.
    try write(
        park: .standard,
        entries: AssetCatalog.entries,
        to: output.deletingLastPathComponent().appending(path: "AppIcon.appiconset"),
        writeContents: true
    )
    for park in Scene.allCases where park != .standard {
        try write(
            park: park,
            entries: AssetCatalog.alternateEntries,
            to: output
                .deletingLastPathComponent()
                .appending(path: "AppIcon-\(park.rawValue).appiconset"),
            writeContents: true
        )
    }
    print("Wrote \(Scene.allCases.count) icons to \(output.deletingLastPathComponent().path())")
    exit(0)
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
