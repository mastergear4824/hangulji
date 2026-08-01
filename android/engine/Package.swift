// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "hangulji-engine",
    // 호스트(macOS) 검증 빌드용 — Android 크로스컴파일에는 영향 없음. core-swift와 동일.
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        // Android용 동적 라이브러리 — libHanguljiEngine.so
        .library(name: "HanguljiEngine", type: .dynamic, targets: ["HanguljiEngine"]),
    ],
    dependencies: [
        .package(path: "../../core-swift"),
        // Global Constraints: core-swift Package.resolved(0.11.2)와 동일 버전 고정
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2"),
    ],
    targets: [
        .target(
            name: "HanguljiEngine",
            dependencies: [
                // path 의존성의 패키지 identity는 디렉터리명(core-swift)
                .product(name: "HanguljiCore", package: "core-swift"),
                // WithDefaultDictionary가 아닌 베이스 모듈 — 사전을 경로로 받는다 (아래 Shim 주석 참조)
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
