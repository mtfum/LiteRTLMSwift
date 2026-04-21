// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiteRTLMSwift",
    platforms: [
        .iOS(.v16),
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
            checksum: "34c4734bdf232384a62be880923dac8debd4632412d0e29484ac463ae66feec5"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.0/GemmaModelConstraintProvider.xcframework.zip",
            checksum: "0ce1cd58f7a35c7dc229c2d425c9ea8dc16e1df49a77a58b7afd5394edfd1de7"
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
