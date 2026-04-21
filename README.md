# LiteRTLMSwift

> **Note**: This is an **unofficial** Swift Package wrapper for [LiteRT-LM](https://ai.google.dev/edge/litert-lm).
> Google has announced that an [official Swift API is coming soon](https://ai.google.dev/edge/litert-lm).
> Once official support is available, this repository will be **archived**.

A Swift Package that wraps the [LiteRT-LM](https://ai.google.dev/edge/litert-lm) on-device LLM engine with a Swift-native API — streaming text generation, audio transcription, and tool calling — for iOS and macOS.

**No bridging header. No manual linker flags. Just `import LiteRTLMSwift`.**

## Requirements

- iOS 16.0+ / macOS 15.0+
- Xcode 16.0+
- A `.litertlm` model file (e.g., `gemma-4-E2B-it.litertlm`)

## Installation

### Swift Package Manager

Add the package in Xcode via **File > Add Package Dependencies...** and enter:

```
https://github.com/mtfum/LiteRTLMSwift
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mtfum/LiteRTLMSwift.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "LiteRTLMSwift", package: "LiteRTLMSwift"),
        ]
    ),
]
```

No additional build settings are required. The package handles `-lc++` and `-all_load` internally.

## Model File

This package provides only the inference engine. Obtain a `.litertlm` model file separately.

Download a compatible model from the [LiteRT-LM releases](https://github.com/google-ai-edge/LiteRT-LM/releases) or convert one using the LiteRT-LM tools.

### Adding the Model to an iOS App

Bundle the `.litertlm` file in your app target, then resolve the path at runtime:

```swift
let modelPath = Bundle.main.urls(forResourcesWithExtension: "litertlm", subdirectory: nil)!.first!.path
```

Or place it in the Documents directory and enable file sharing in `Info.plist`:

```xml
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

## Usage

### Initialize the Engine

```swift
import LiteRTLMSwift

let engine = try LiteRTLMEngine(modelPath: modelPath, maxTokens: 2048)
```

`LiteRTLMEngine` is `@unchecked Sendable` and safe to use from any concurrency context.

### Text Generation (Streaming)

```swift
let prompt = "<|turn>user\nExplain quantum computing in one paragraph.<turn|>\n<|turn>model\n\n"

var response = ""
for await chunk in engine.generate(prompt: prompt) {
    response += chunk
    print(chunk, terminator: "")
}
```

### Audio Transcription (Streaming)

Provide raw PCM audio: 16 kHz, mono, Float32.

```swift
let pcmData: Data = /* 16kHz mono Float32 PCM */

var transcript = ""
for await chunk in engine.transcribeAudio(pcmData: pcmData) {
    transcript += chunk
}
```

For long recordings, split audio into chunks and transcribe sequentially:

```swift
let chunks: [Data] = /* 30-second PCM chunks */

for await text in engine.transcribeAudioChunks(chunks) {
    transcript += text
}
```

### Tool Calling (Experimental)

```swift
let prompt = """
<|turn>system
<|tool>declaration:getWeather{description:"get current weather",parameters:{city:{type:"STRING"}}}<tool|>
<turn|>
<|turn>user
What's the weather in Tokyo?
<turn|>
<|turn>model

"""

for await chunk in engine.generateWithToolCalling(
    prompt: prompt,
    onToolCall: { funcName, argsJSON in
        // Called when the model invokes a tool
        print("Tool: \(funcName), args: \(argsJSON)")
        return """{"temperature": 22, "condition": "sunny"}"""
    }
) {
    print(chunk, terminator: "")
}
```

### Reset Session (Clear KV Cache)

Call `resetSession()` between independent inference calls to clear the KV cache:

```swift
try engine.resetSession()
```

## API Reference

```swift
public final class LiteRTLMEngine: @unchecked Sendable {

    /// Initializes the engine and creates an inference session.
    public init(modelPath: String, maxTokens: Int = 2048) throws

    /// Clears the KV cache by recreating the session. Call between independent inferences.
    public func resetSession() throws

    /// Streams generated tokens for a text prompt.
    public func generate(prompt: String) -> AsyncStream<String>

    /// Streams transcription from raw PCM audio (16 kHz, mono, Float32).
    public func transcribeAudio(pcmData: Data) -> AsyncStream<String>

    /// Transcribes multiple PCM chunks sequentially, yielding text per chunk.
    public func transcribeAudioChunks(_ chunks: [Data]) -> AsyncStream<String>

    /// Generates with tool-calling support. Invokes `onToolCall` when the model calls a tool.
    public func generateWithToolCalling(
        prompt: String,
        onToolCall: @Sendable @escaping (String, String) async -> String
    ) -> AsyncStream<String>
}
```

## What's Included

| Component | Description |
|---|---|
| `LiteRTLMSwift` (Swift) | `LiteRTLMEngine` — Swift wrapper with async streaming API |
| `LiteRTLM` (C static lib) | LiteRT-LM inference engine xcframework |
| `GemmaModelConstraintProvider` (dynamic lib) | Structured Output / Function Calling support |

## Known Limitations

- **CPU only**: GPU backend is not yet available in upstream LiteRT-LM (see [issue #1050](https://github.com/google-ai-edge/LiteRT-LM/issues/1050))
- **Apple Silicon only**: arm64 only — no iOS x86_64 simulator
- **Performance**: ~9–10 tokens/sec on iPhone (Gemma 4 E2B-it, CPU)
- **Memory**: ~961 MB for Gemma 4 E2B-it

## Based On

- [LiteRT-LM v0.10.2](https://github.com/google-ai-edge/LiteRT-LM/tree/v0.10.2)
- Build instructions: [build-litert-lm.md](build-litert-lm.md)

## License

This package is licensed under the [MIT License](LICENSE).

The LiteRT-LM engine is licensed under the [Apache License 2.0](https://github.com/google-ai-edge/LiteRT-LM/blob/main/LICENSE).

Model files (e.g., Gemma) are subject to their own license terms.
