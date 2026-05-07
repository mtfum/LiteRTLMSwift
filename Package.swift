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
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/LiteRTLM_0.2.0.xcframework.zip",
            checksum: "23d3e376a8996824870c6d9617b3ec3d5d463a27db872b5dd5a21e2d9bd43951"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/GemmaModelConstraintProvider_0.2.0.xcframework.zip",
            checksum: "12896ba25f3e1cb38f7b8295e029e77ead62cfaf48896b7d5888e96d33556d08"
        ),
        .binaryTarget(
            name: "LiteRtMetalAccelerator",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/LiteRtMetalAccelerator_0.2.0.xcframework.zip",
            checksum: "63c012e45c213d6e246cc7e2e897c7130a5a61469a02af9b56560521261b2f94"
        ),
        .binaryTarget(
            name: "LiteRtTopKMetalSampler",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/LiteRtTopKMetalSampler_0.2.0.xcframework.zip",
            checksum: "a6cb2fa8d2f2ebc48bf7c812d0d5d20ed3e4c70abb838b08803506cb3ed798a9"
        ),
        .target(
            name: "LiteRTLMSwift",
            dependencies: ["LiteRTLM", "GemmaModelConstraintProvider",
                           "LiteRtMetalAccelerator", "LiteRtTopKMetalSampler"],
            path: "Sources/LiteRTLMSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
