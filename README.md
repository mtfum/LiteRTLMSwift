# LiteRTLMSwift

A Swift Package for distributing [LiteRT-LM](https://ai.google.dev/edge/litert) xcframework for iOS and macOS.

## Requirements

- iOS 16.0+
- macOS 13.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mtfum/LiteRTLMSwift.git", from: "0.1.0"),
]
```

Then add `LiteRTLM` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "LiteRTLM", package: "LiteRTLMSwift"),
    ]
),
```

Or in Xcode: **File > Add Package Dependencies...** and enter the repository URL.

## License

See [LICENSE](LICENSE) for details.