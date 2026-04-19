// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiteRTLMSwift",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "LiteRTLM",
            targets: ["LiteRTLM"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "LiteRTLM",
            url: "https://github.com/mtfum/LiteRTLMSwift/releases/download/0.1.0/LiteRTLM.xcframework.zip",
            checksum: "6362074716e913deedb20016effa7fcb93fffcb78405b6c7f2dc324c5d6ced21"
        ),
    ]
)
