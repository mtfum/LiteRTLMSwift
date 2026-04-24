// swift-tools-version: 6.0

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
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.5/LiteRTLM_0.1.5.xcframework.zip",
            checksum: "62e5d5226d6dad889fe790037a792c6519609e4f4995e2a25f0cd767a4e9c1bd"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.5/GemmaModelConstraintProvider_0.1.5.xcframework.zip",
            checksum: "b584f8c2ec3920c7de927f01101761cd4fe63f7c82a4e242d12efb13aed44daa"
        ),
        .target(
            name: "LiteRTLMSwift",
            dependencies: ["LiteRTLM", "GemmaModelConstraintProvider"],
            path: "Sources/LiteRTLMSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
