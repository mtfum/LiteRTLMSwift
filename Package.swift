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
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.0/LiteRTLM.xcframework.zip",
            checksum: "11fa21ba9617f5ca1b6162501b2fa5d34e4d8ea8f15eba408ace10be9a64dd32"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.3/GemmaModelConstraintProvider.xcframework.zip",
            checksum: "753c4aae1870cc88f9752c164a670cb9e9df9e1475237fbe9208f43cd71cbc4f"
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
