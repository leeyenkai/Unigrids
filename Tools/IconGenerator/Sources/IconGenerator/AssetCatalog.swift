import Foundation

enum Variant {
    case light
    case dark
    case tinted

    var palette: Palette {
        switch self {
        case .light: .light
        case .dark: .dark
        case .tinted: .tinted
        }
    }

    /// The `appearances` value Xcode expects, or `nil` for the default entry.
    var appearance: String? {
        switch self {
        case .light: nil
        case .dark: "dark"
        case .tinted: "tinted"
        }
    }
}

/// One image in `AppIcon.appiconset`.
struct CatalogEntry {
    let filename: String
    let idiom: String
    let platform: String?
    let scale: String?
    let size: String
    let variant: Variant
    /// The size the file is actually rendered at, which for a 2x entry is twice the
    /// nominal one.
    let pixels: Int
}

enum AssetCatalog {
    static let entries: [CatalogEntry] = ios + mac

    /// What an alternate icon needs: the three iOS appearances and nothing else.
    ///
    /// macOS has no runtime icon switching — `setAlternateIconName` is UIKit only — so
    /// the ten macOS sizes would be ten unreferenced files per park, ninety in all.
    static let alternateEntries: [CatalogEntry] = ios

    private static let ios: [CatalogEntry] = [
        CatalogEntry(
            filename: "icon-1024.png",
            idiom: "universal",
            platform: "ios",
            scale: nil,
            size: "1024x1024",
            variant: .light,
            pixels: 1024
        ),
        CatalogEntry(
            filename: "icon-1024-dark.png",
            idiom: "universal",
            platform: "ios",
            scale: nil,
            size: "1024x1024",
            variant: .dark,
            pixels: 1024
        ),
        CatalogEntry(
            filename: "icon-1024-tinted.png",
            idiom: "universal",
            platform: "ios",
            scale: nil,
            size: "1024x1024",
            variant: .tinted,
            pixels: 1024
        ),
    ]

    private static let mac: [CatalogEntry] = [16, 32, 128, 256, 512].flatMap { nominal in
        [1, 2].map { factor in
            CatalogEntry(
                filename: "icon-mac-\(nominal)\(factor == 2 ? "@2x" : "").png",
                idiom: "mac",
                platform: nil,
                scale: "\(factor)x",
                size: "\(nominal)x\(nominal)",
                variant: .light,
                pixels: nominal * factor
            )
        }
    }

    /// `Contents.json`, in Xcode's own formatting so the file does not churn when
    /// Xcode next touches it.
    static func contentsJSON(for entries: [CatalogEntry] = entries) -> String {
        var lines = ["{", "  \"images\" : ["]
        for (index, entry) in entries.enumerated() {
            lines.append(contentsOf: block(for: entry, isLast: index == entries.count - 1))
        }
        lines.append(contentsOf: [
            "  ],",
            "  \"info\" : {",
            "    \"author\" : \"xcode\",",
            "    \"version\" : 1",
            "  }",
            "}",
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    private static func block(for entry: CatalogEntry, isLast: Bool) -> [String] {
        var fields: [String] = []
        if let appearance = entry.appearance {
            fields.append(contentsOf: [
                "\"appearances\" : [",
                "  {",
                "    \"appearance\" : \"luminosity\",",
                "    \"value\" : \"\(appearance)\"",
                "  }",
                "],",
            ])
        }
        var tail = ["\"filename\" : \"\(entry.filename)\"", "\"idiom\" : \"\(entry.idiom)\""]
        if let platform = entry.platform {
            tail.append("\"platform\" : \"\(platform)\"")
        }
        if let scale = entry.scale {
            tail.append("\"scale\" : \"\(scale)\"")
        }
        tail.append("\"size\" : \"\(entry.size)\"")
        fields.append(contentsOf: tail.enumerated().map { index, field in
            index == tail.count - 1 ? field : field + ","
        })
        return ["    {"] + fields.map { "      " + $0 } + ["    }" + (isLast ? "" : ",")]
    }
}

extension CatalogEntry {
    fileprivate var appearance: String? {
        variant.appearance
    }
}
