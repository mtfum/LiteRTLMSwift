# LiteRTLMSwift

> **Note**: This is an **unofficial** Swift Package wrapper for [LiteRT-LM](https://ai.google.dev/edge/litert-lm).
> Google has announced that an [official Swift API is coming soon](https://ai.google.dev/edge/litert-lm).
> Once official support is available, this repository will be **archived**.

A Swift Package for distributing the [LiteRT-LM](https://ai.google.dev/edge/litert-lm) xcframework for iOS and macOS.

## Requirements

- iOS 16.0+ / macOS 13.0+
- Xcode 16.0+
- A `.litertlm` model file (e.g., `gemma-4-E2B-it.litertlm`)

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mtfum/LiteRTLMSwift.git", from: "0.3.0"),
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

#### Other Linker Flags

`-force_load` is required because LiteRT-LM registers CPU/GPU executors via static initializers. Without it, the linker strips these symbols, causing `Engine type not found: 1` at runtime.

| Platform | Other Linker Flags |
|---|---|
| **iOS** | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertlmswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/LiteRTLM_arm64.a` |
| **iOS Simulator** | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertlmswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64-simulator/LiteRTLM_sim_arm64.a` |
| **macOS** | `-lc++ -force_load $(BUILD_DIR)/../../SourcePackages/artifacts/litertlmswift/LiteRTLM/LiteRTLM.xcframework/macos-arm64/LiteRTLM_macos_arm64.a` |

> **Tip**: Use per-SDK build settings in Xcode (`OTHER_LDFLAGS[sdk=iphoneos*]`, `OTHER_LDFLAGS[sdk=iphonesimulator*]`, `OTHER_LDFLAGS[sdk=macosx*]`) to apply the correct path for each platform automatically.

#### Bridging Header

Create a bridging header and import `engine.h`:

```objc
#import "engine.h"
```

Set **Header Search Paths** to include both device and simulator headers:

```
$(BUILD_DIR)/../../SourcePackages/artifacts/litertlmswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64/Headers
$(BUILD_DIR)/../../SourcePackages/artifacts/litertlmswift/LiteRTLM/LiteRTLM.xcframework/ios-arm64-simulator/Headers
```

> **Note**: The artifact directory name is `litertlmswift` (all lowercase, no hyphens), derived from the package identity.

## Model File

This package provides only the inference engine. You need to obtain a `.litertlm` model file separately.

### Obtaining a Model

Download a compatible model from the [LiteRT-LM releases](https://github.com/google-ai-edge/LiteRT-LM/releases) or convert one using the LiteRT-LM tools.

### Placing the Model (iOS)

Place the `.litertlm` file in your app's Documents directory. To enable file transfer via iTunes/Finder, add to your `Info.plist`:

```xml
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

Then resolve the path at runtime:

```swift
let modelPath = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("gemma-4-E2B-it.litertlm")
    .path
```

### Placing the Model (macOS)

Place the `.litertlm` file in your app's sandbox container or bundle it as a resource. You can also use `NSOpenPanel` to let the user select the file at runtime.

## Usage

```swift
import Foundation

// Inference must run on a thread with a large stack size (16 MB+)
let thread = Thread {
    let modelPath = /* path to .litertlm file */

    // 1. Create engine
    let settings = litert_lm_engine_settings_create(modelPath, "cpu", nil, "cpu")!
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
- **Apple Silicon only**: macOS support is arm64 only (no Intel)
- **Performance**: ~9-10 tokens/sec on iPhone (Gemma 4 E2B-it, CPU)
- **Memory**: ~961 MB for Gemma 4 E2B-it model
- **C API only**: No Swift wrapper is provided yet. You must use the C API via a bridging header.

## What's Included

| Binary Target | Description |
|---|---|
| `LiteRTLM` | LiteRT-LM inference engine (static xcframework) |
| `GemmaModelConstraintProvider` | Structured Output / Function Calling support (dynamic xcframework, embedded automatically) |

Both are included when you add the `LiteRTLM` product to your target.

## Based On

- [LiteRT-LM v0.10.1](https://github.com/google-ai-edge/LiteRT-LM/tree/v0.10.1)
- Build instructions: [build-litert-lm.md](build-litert-lm.md)

## License

This package is licensed under the [MIT License](LICENSE).

The LiteRT-LM engine is licensed under the [Apache License 2.0](https://github.com/google-ai-edge/LiteRT-LM/blob/main/LICENSE).

Model files (e.g., Gemma) are subject to their own license terms.
