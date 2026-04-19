# LiteRTLMSwift

> **Note**: This is an **unofficial** Swift Package wrapper for [LiteRT-LM](https://ai.google.dev/edge/litert-lm).
> Google has announced that an [official Swift API is coming soon](https://ai.google.dev/edge/litert-lm).
> Once the official iOS support is available, this repository will be **archived**.

A Swift Package for distributing the [LiteRT-LM](https://ai.google.dev/edge/litert-lm) xcframework for iOS.

## Requirements

- iOS 16.0+
- Xcode 16.0+
- A `.litertlm` model file (e.g., `gemma-4-E2B-it.litertlm`)

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

### Required Xcode Build Settings

This package provides the LiteRT-LM static library as an xcframework. You **must** configure the following build settings in your Xcode project:

| Setting | Value |
|---|---|
| **Other Linker Flags** | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/LiteRTLM_arm64.a` |
| **Swift Objective-C Bridging Header** | Path to your bridging header |
| **Header Search Paths** | `$(BUILD_DIR)/../../SourcePackages/artifacts/litertmlswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/Headers` |

> **Why `-force_load`?** LiteRT-LM registers CPU/GPU executors via static initializers. Without `-force_load`, the linker strips these symbols, causing `Engine type not found: 1` at runtime.

### Bridging Header

Create a bridging header and import `engine.h`:

```objc
#import "engine.h"
```

## Model File

This package provides only the inference engine. You need to obtain a `.litertlm` model file separately.

### Obtaining a Model

Download a compatible model from the [LiteRT-LM releases](https://github.com/google-ai-edge/LiteRT-LM/releases) or convert one using the LiteRT-LM tools.

### Placing the Model

Place the `.litertlm` file in your app's Documents directory. To enable file transfer via iTunes/Finder, add to your `Info.plist`:

```xml
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

## Usage

```swift
import Foundation

// Inference must run on a thread with a large stack size (16 MB+)
let thread = Thread {
    let modelPath = /* path to .litertlm file */

    // 1. Create engine
    let settings = litert_lm_engine_settings_create(modelPath, "cpu", nil, nil)!
    defer { litert_lm_engine_settings_delete(settings) }

    let engine = litert_lm_engine_create(settings)!
    defer { litert_lm_engine_delete(engine) }

    // 2. Create session
    let session = litert_lm_engine_create_session(engine, nil)!
    defer { litert_lm_session_delete(session) }

    // 3. Generate content
    var input = "Hello, world!".withCString { cStr -> InputData in
        InputData(type: kInputText, data: cStr, size: strlen(cStr))
    }
    let responses = litert_lm_session_generate_content(session, &input, 1)!
    defer { litert_lm_responses_delete(responses) }

    let text = String(cString: litert_lm_responses_get_response_text_at(responses, 0))
    print(text)
}
thread.stackSize = 16 * 1024 * 1024
thread.start()
```

> **Important**: The inference thread requires at least **16 MB** of stack size. The default thread stack (512 KB - 1 MB) will cause `EXC_BAD_ACCESS` crashes.

## Known Limitations

- **CPU only**: GPU backend is not yet available in the upstream LiteRT-LM v0.10.1 (see [issue #1050](https://github.com/google-ai-edge/LiteRT-LM/issues/1050))
- **Performance**: ~9-10 tokens/sec on iPhone (Gemma 4 E2B-it, CPU)
- **Memory**: ~961 MB for Gemma 4 E2B-it model
- **C API only**: No Swift wrapper is provided yet. You must use the C API via a bridging header.

## Based On

- [LiteRT-LM v0.10.1](https://github.com/google-ai-edge/LiteRT-LM/tree/v0.10.1)
- Build instructions: [build-litert-lm-ios.md](build-litert-lm-ios.md)

## License

This package is licensed under the [MIT License](LICENSE).

The LiteRT-LM engine is licensed under the [Apache License 2.0](https://github.com/google-ai-edge/LiteRT-LM/blob/main/LICENSE).

Model files (e.g., Gemma) are subject to their own license terms.
