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
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.4/GemmaModelConstraintProvider_0.1.4.xcframework.zip",
            checksum: "8a95d84322981ab3babf745f8cdfe64634bef5b89e23266793bc6d3a110f5948"
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
