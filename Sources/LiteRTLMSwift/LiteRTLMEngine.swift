import Foundation
import LiteRTLM

/// Swift wrapper around the LiteRT-LM C API.
/// Runs inference on a dedicated thread with a large stack (required by LiteRT-LM).
public final class LiteRTLMEngine: @unchecked Sendable {

    public enum LiteRTError: Swift.Error, LocalizedError {
        case settingsCreationFailed
        case engineCreationFailed
        case sessionCreationFailed

        public var errorDescription: String? {
            switch self {
            case .settingsCreationFailed: "Failed to create engine settings"
            case .engineCreationFailed:   "Failed to initialize engine (check model path)"
            case .sessionCreationFailed:  "Failed to create inference session"
            }
        }
    }

    private let enginePtr: OpaquePointer
    private var sessionPtr: OpaquePointer

    /// Initializes the LiteRT-LM engine and creates an inference session.
    /// - Parameters:
    ///   - modelPath: Absolute path to a `.litertlm` model file.
    ///   - maxTokens: Maximum token context length. Defaults to 2048.
    public init(modelPath: String, maxTokens: Int = 2048) throws {
        guard let settings = litert_lm_engine_settings_create(modelPath, "cpu", nil, "cpu") else {
            throw LiteRTError.settingsCreationFailed
        }
        litert_lm_engine_settings_set_max_num_tokens(settings, Int32(maxTokens))
        litert_lm_engine_settings_set_prefill_chunk_size(settings, 128)
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path {
            litert_lm_engine_settings_set_cache_dir(settings, cacheDir)
        }
        defer { litert_lm_engine_settings_delete(settings) }

        guard let engine = litert_lm_engine_create(settings) else {
            throw LiteRTError.engineCreationFailed
        }

        guard let session = litert_lm_engine_create_session(engine, nil) else {
            litert_lm_engine_delete(engine)
            throw LiteRTError.sessionCreationFailed
        }

        self.enginePtr = engine
        self.sessionPtr = session
    }

    deinit {
        litert_lm_session_delete(sessionPtr)
        litert_lm_engine_delete(enginePtr)
    }

    /// Clears the KV cache by recreating the session.
    /// Call between independent inferences. Do not call while inference is in progress.
    public func resetSession() throws {
        litert_lm_session_delete(sessionPtr)
        guard let newSession = litert_lm_engine_create_session(enginePtr, nil) else {
            throw LiteRTError.sessionCreationFailed
        }
        sessionPtr = newSession
    }

    // MARK: - Public API

    /// Streams transcription tokens from raw PCM audio.
    /// - Parameter pcmData: Raw audio in 16 kHz, mono, Float32 format.
    /// - Returns: An `AsyncStream` that yields transcription tokens as they are generated.
    public func transcribeAudio(pcmData: Data) -> AsyncStream<String> {
        makeInterleavedStream(pcmData: pcmData)
    }

    /// Streams generated tokens for a text-only prompt.
    /// - Parameter prompt: The full prompt string including any turn markers.
    /// - Returns: An `AsyncStream` that yields tokens as they are generated.
    public func generate(prompt: String) -> AsyncStream<String> {
        makeSessionStream(prompt: prompt)
    }

    /// Transcribes multiple PCM chunks sequentially, yielding accumulated text per chunk.
    /// - Parameter chunks: An array of raw PCM audio chunks (16 kHz, mono, Float32).
    /// - Returns: An `AsyncStream` that yields the transcription for each chunk in order.
    public func transcribeAudioChunks(_ chunks: [Data]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                for (index, chunk) in chunks.enumerated() {
                    var chunkText = ""
                    for await token in self.transcribeAudio(pcmData: chunk) {
                        chunkText += token
                    }
                    if !chunkText.isEmpty {
                        continuation.yield(chunkText + (index < chunks.count - 1 ? "\n" : ""))
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Streams generated tokens with tool-calling support (experimental).
    ///
    /// When the model emits a tool-call token sequence, `onToolCall` is invoked with
    /// the function name and a JSON-encoded arguments string. The return value is fed
    /// back to the model as a tool response, and generation continues.
    ///
    /// - Parameters:
    ///   - prompt: The full prompt string including system tool declarations and turn markers.
    ///   - onToolCall: Called when the model invokes a tool. Receives `(functionName, argsJSON)`
    ///     and must return the tool result as a string.
    /// - Returns: An `AsyncStream` that yields the final response tokens after tool resolution.
    public func generateWithToolCalling(
        prompt: String,
        onToolCall: @Sendable @escaping (String, String) async -> String
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                var fullResponse = ""
                for await chunk in self.generate(prompt: prompt) {
                    fullResponse += chunk
                }

                let pattern = #"<\|tool_call\>call:(\w+)\{(.*?)\}<tool_call\|>"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                   let match = regex.firstMatch(in: fullResponse,
                                                range: NSRange(fullResponse.startIndex..., in: fullResponse)),
                   match.numberOfRanges == 3,
                   let nameRange = Range(match.range(at: 1), in: fullResponse),
                   let argsRange = Range(match.range(at: 2), in: fullResponse) {

                    let funcName = String(fullResponse[nameRange])
                    let argsJSON = "{\(String(fullResponse[argsRange]))}"

                    let toolResult = await onToolCall(funcName, argsJSON)
                    let continuationPrompt = """
                    \(prompt)\(fullResponse)
                    <|tool_response>response:\(funcName){value:"\(toolResult)"}<tool_response|>
                    <|turn>model

                    """
                    for await chunk in self.generate(prompt: continuationPrompt) {
                        continuation.yield(chunk)
                    }
                } else {
                    continuation.yield(fullResponse)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Private

    private func makeBlockingAudioStream(pcmData: Data) -> AsyncStream<String> {
        let session = sessionPtr
        let prefix = "<|turn>user\n"
        let suffix = "\nTranscribe this audio<turn|>\n<|turn>model\n"

        return AsyncStream { continuation in
            let thread = Thread {
                prefix.withCString { prefixPtr in
                    suffix.withCString { suffixPtr in
                        pcmData.withUnsafeBytes { rawBuffer in
                            var inputs: [InputData] = [
                                InputData(type: kInputText,
                                          data: UnsafeRawPointer(prefixPtr),
                                          size: prefix.utf8.count),
                                InputData(type: kInputAudio,
                                          data: rawBuffer.baseAddress,
                                          size: pcmData.count),
                                InputData(type: kInputAudioEnd,
                                          data: nil,
                                          size: 0),
                                InputData(type: kInputText,
                                          data: UnsafeRawPointer(suffixPtr),
                                          size: suffix.utf8.count),
                            ]
                            if let responses = litert_lm_session_generate_content(
                                session, &inputs, inputs.count) {
                                let count = litert_lm_responses_get_num_candidates(responses)
                                for i in 0..<count {
                                    if let cstr = litert_lm_responses_get_response_text_at(responses, i) {
                                        let text = String(cString: cstr)
                                        if !text.isEmpty { continuation.yield(text) }
                                    }
                                }
                                litert_lm_responses_delete(responses)
                            }
                            continuation.finish()
                        }
                    }
                }
            }
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }

    private func makeConversationAudioStream(pcmData: Data) -> AsyncStream<String> {
        return AsyncStream { continuation in
            guard let configPtr = litert_lm_conversation_config_create(
                self.enginePtr, nil, nil, nil, nil, false) else {
                continuation.finish()
                return
            }
            guard let convPtr = litert_lm_conversation_create(self.enginePtr, configPtr) else {
                litert_lm_conversation_config_delete(configPtr)
                continuation.finish()
                return
            }
            litert_lm_conversation_config_delete(configPtr)

            let box = ConvContinuationBox(continuation, convPtr)
            let boxPtr = Unmanaged.passRetained(box).toOpaque()

            let callback: LiteRtLmStreamCallback = { boxPtr, chunk, isFinal, errorMsg in
                guard let boxPtr else { return }
                let box = Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr).takeUnretainedValue()
                if let chunk {
                    let text = String(cString: chunk)
                    if !text.isEmpty { box.continuation.yield(text) }
                }
                if isFinal {
                    box.continuation.finish()
                    Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr).release()
                }
            }

            let base64Audio = pcmData.base64EncodedString()
            let messageJSON = """
            {"role":"user","content":[{"type":"audio","inline_data":{"mime_type":"audio/pcm;rate=16000","data":"\(base64Audio)"}},{"type":"text","text":"Transcribe this audio"}]}
            """

            let thread = Thread {
                let rc = litert_lm_conversation_send_message_stream(
                    convPtr, messageJSON, nil, callback, boxPtr)
                if rc != 0 {
                    Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr)
                        .takeRetainedValue().continuation.finish()
                }
            }
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }

    private func makeInterleavedStream(pcmData: Data) -> AsyncStream<String> {
        let session = sessionPtr

        let prefix = "<|turn>user\n"
        let suffix = "\nTranscribe this audio<turn|>\n<|turn>model\n"

        return AsyncStream { continuation in
            let box = ContinuationBox(continuation)
            let boxPtr = Unmanaged.passRetained(box).toOpaque()

            let callback: LiteRtLmStreamCallback = { boxPtr, chunk, isFinal, errorMsg in
                guard let boxPtr else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(boxPtr).takeUnretainedValue()
                if let chunk {
                    let text = String(cString: chunk)
                    if !text.isEmpty { box.continuation.yield(text) }
                }
                if isFinal {
                    box.continuation.finish()
                    Unmanaged<ContinuationBox>.fromOpaque(boxPtr).release()
                }
            }

            let thread = Thread {
                prefix.withCString { prefixPtr in
                    suffix.withCString { suffixPtr in
                        pcmData.withUnsafeBytes { rawBuffer in
                            var inputs: [InputData] = [
                                InputData(type: kInputText,
                                          data: UnsafeRawPointer(prefixPtr),
                                          size: prefix.utf8.count),
                                InputData(type: kInputAudio,
                                          data: rawBuffer.baseAddress,
                                          size: pcmData.count),
                                InputData(type: kInputAudioEnd,
                                          data: nil,
                                          size: 0),
                                InputData(type: kInputText,
                                          data: UnsafeRawPointer(suffixPtr),
                                          size: suffix.utf8.count),
                            ]
                            let rc = litert_lm_session_generate_content_stream(
                                session, &inputs, inputs.count, callback, boxPtr)
                            if rc != 0 {
                                Unmanaged<ContinuationBox>.fromOpaque(boxPtr)
                                    .takeRetainedValue().continuation.finish()
                            }
                        }
                    }
                }
            }
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }

    private func makeSessionStream(prompt: String) -> AsyncStream<String> {
        let session = sessionPtr
        return AsyncStream { continuation in
            let box = ContinuationBox(continuation)
            let boxPtr = Unmanaged.passRetained(box).toOpaque()

            let callback: LiteRtLmStreamCallback = { boxPtr, chunk, isFinal, errorMsg in
                guard let boxPtr else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(boxPtr).takeUnretainedValue()
                if let chunk {
                    let text = String(cString: chunk)
                    if !text.isEmpty { box.continuation.yield(text) }
                }
                if isFinal {
                    box.continuation.finish()
                    Unmanaged<ContinuationBox>.fromOpaque(boxPtr).release()
                }
            }

            let thread = Thread {
                prompt.withCString { promptPtr in
                    var inputs: [InputData] = [
                        InputData(type: kInputText,
                                  data: UnsafeRawPointer(promptPtr),
                                  size: prompt.utf8.count),
                    ]
                    let rc = litert_lm_session_generate_content_stream(
                        session, &inputs, inputs.count, callback, boxPtr)
                    if rc != 0 {
                        Unmanaged<ContinuationBox>.fromOpaque(boxPtr)
                            .takeRetainedValue().continuation.finish()
                    }
                }
            }
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }
}

private final class ContinuationBox: @unchecked Sendable {
    let continuation: AsyncStream<String>.Continuation
    init(_ continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }
}

private final class ConvContinuationBox: @unchecked Sendable {
    let continuation: AsyncStream<String>.Continuation
    let convPtr: OpaquePointer
    init(_ continuation: AsyncStream<String>.Continuation, _ convPtr: OpaquePointer) {
        self.continuation = continuation
        self.convPtr = convPtr
    }
    deinit { litert_lm_conversation_delete(convPtr) }
}
