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
            checksum: "b26884f8214dd12560c9e3f4f6a5b0d1c7472bb9a4d353c763fa40a8ea566293"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/GemmaModelConstraintProvider_0.2.0.xcframework.zip",
            checksum: "243ff346cf72213566853cb598a1d3a90cd1fd1f79a081880dcbc419d8c67a9b"
        ),
        .binaryTarget(
            name: "LiteRt",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/LiteRt_0.2.0.xcframework.zip",
            checksum: "5065635c2747710c222c471aa873fb3b33660df3612b68817477094dd4db105b"
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
                           "LiteRt", "LiteRtMetalAccelerator", "LiteRtTopKMetalSampler"],
            path: "Sources/LiteRTLMSwift",
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
