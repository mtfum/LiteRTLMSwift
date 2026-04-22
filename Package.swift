// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LiteRTLMSwift",
    platforms: [
        .iOS(.v16),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "LiteRTLMSwift",
            targets: ["LiteRTLMSwift"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "LiteRTLM",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.0/LiteRTLM.xcframework.zip",
            checksum: "11fa21ba9617f5ca1b6162501b2fa5d34e4d8ea8f15eba408ace10be9a64dd32"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.1/GemmaModelConstraintProvider.xcframework.zip",
            checksum: "d9fb8e330697ec88500b55b18022d27e43d598a87203c0b2f8bbaf97cd69a272"
        ),
        .target(
            name: "LiteRTLMSwift",
            dependencies: ["LiteRTLM", "GemmaModelConstraintProvider"],
            path: "Sources/LiteRTLMSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
                .unsafeFlags(["-all_load"]),
            ]
        ),
    ]
)
