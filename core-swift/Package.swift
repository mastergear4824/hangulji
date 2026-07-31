// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HanguljiCore", targets: ["HanguljiCore"]),
        .library(name: "HanguljiConversion", targets: ["HanguljiConversion"]),
    ],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.11.0")),
    ],
    targets: [
        .target(
            name: "HanguljiCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "HanguljiConversion",
            dependencies: [
                "HanguljiCore",
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary",
                         package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "fixture-export",
            dependencies: ["HanguljiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiCoreTests",
            dependencies: ["HanguljiCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HanguljiConversionTests",
            dependencies: ["HanguljiConversion"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
