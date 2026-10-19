// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconGenerator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "IconGenerator", path: "Sources/IconGenerator"),
    ]
)
