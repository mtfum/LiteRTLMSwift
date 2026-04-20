// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiteRTLMSwift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LiteRTLM",
            targets: ["LiteRTLM", "GemmaModelConstraintProvider"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "LiteRTLM",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.2.0/LiteRTLM.xcframework.zip",
            checksum: "0480e926868c276171d172b964f8d9733615f0d863d32faf14fd5b93e5ba8aa7"
        ),
        .binaryTarget(
            name: "GemmaModelConstraintProvider",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.3.0/GemmaModelConstraintProvider.xcframework.zip",
            checksum: "594e5dcef7dea39f119cd3ab2858c2b322ca97f9d25f386159a0936443111bbc"
        ),
    ]
)
