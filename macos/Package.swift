// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-macos",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "hangulji-core", path: "../core-swift"),
    ],
    targets: [
        .executableTarget(
            name: "Hangulji",
            dependencies: [
                .product(name: "HanguljiCore", package: "hangulji-core"),
                .product(name: "HanguljiConversion", package: "hangulji-core"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
