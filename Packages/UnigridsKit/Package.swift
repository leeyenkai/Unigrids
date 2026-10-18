// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UnigridsKit",
    platforms: [
        // Latest OS generation only (SPECIFICATION.md §3). Raise the floor rather than
        // adding availability fallbacks.
        .iOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "UnigridsKit", targets: ["UnigridsFeatures"]),
        .library(name: "UnigridsCore", targets: ["UnigridsCore"]),
        .library(name: "UnigridsReference", targets: ["UnigridsReference"]),
        .library(name: "UnigridsLog", targets: ["UnigridsLog"]),
        .library(name: "UnigridsDesign", targets: ["UnigridsDesign"]),
    ],
    targets: [
        // Domain model and pure rules. Foundation only — see AGENTS.md §1.
        .target(name: "UnigridsCore"),

        // Read-only reference data bundled with the app.
        .target(
            name: "UnigridsReference",
            dependencies: ["UnigridsCore"],
            // `.copy` rather than `.process`: processing flattens the directory
            // structure, and the guides live in their own subdirectory.
            resources: [.copy("Resources/reference")]
        ),

        // SwiftData user store, synced through the user's private CloudKit database.
        .target(name: "UnigridsLog", dependencies: ["UnigridsCore"]),

        // Unigrid design system plus native design tokens.
        .target(name: "UnigridsDesign", dependencies: ["UnigridsCore"]),

        // SwiftUI screens.
        .target(
            name: "UnigridsFeatures",
            dependencies: ["UnigridsCore", "UnigridsReference", "UnigridsLog", "UnigridsDesign"]
        ),

        .testTarget(name: "UnigridsCoreTests", dependencies: ["UnigridsCore"]),
        .testTarget(
            name: "UnigridsReferenceTests",
            dependencies: ["UnigridsReference", "UnigridsCore"]
        ),
        .testTarget(name: "UnigridsLogTests", dependencies: ["UnigridsLog", "UnigridsCore"]),
    ],
    swiftLanguageModes: [.v6]
)
