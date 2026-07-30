// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HanguljiCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiCoreTests",
            dependencies: ["HanguljiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
