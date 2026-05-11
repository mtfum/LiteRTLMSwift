import Foundation
import LiteRTLM

/// Swift wrapper around the LiteRT-LM C API.
/// Runs inference on a dedicated thread with a large stack (required by LiteRT-LM).
public final class LiteRTLMEngine: @unchecked Sendable {

    public enum Backend { case cpu, gpu }

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
    private var sessionPtr: OpaquePointer?

    /// Initializes the LiteRT-LM engine and creates an inference session.
    /// - Parameters:
    ///   - modelPath: Absolute path to a `.litertlm` model file.
    ///   - maxTokens: Maximum token context length. `0` (default) lets the engine use the value
    ///     embedded in the model file (e.g. 128k for Gemma 4).
    ///   - backend: Compute backend. `.cpu` (default) or `.gpu` (Metal, device only).
    public init(modelPath: String, maxTokens: Int = 0, backend: Backend = .cpu) throws {
        let backendStr = backend == .gpu ? "gpu" : "cpu"
        // Audio/vision sections in current models carry a cpu-only backend constraint,
        // so always use "cpu" for those regardless of the main backend.
        guard let settings = litert_lm_engine_settings_create(modelPath, backendStr, nil, "cpu") else {
            throw LiteRTError.settingsCreationFailed
        }
        if maxTokens > 0 {
            litert_lm_engine_settings_set_max_num_tokens(settings, Int32(maxTokens))
        }
        if backend == .cpu {
            litert_lm_engine_settings_set_prefill_chunk_size(settings, 128)
        }
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path {
            litert_lm_engine_settings_set_cache_dir(settings, cacheDir)
        }
        if backend == .gpu {
            litert_lm_engine_settings_set_enable_speculative_decoding(settings, true)
        }
        defer { litert_lm_engine_settings_delete(settings) }

        // On devices with insufficient GPU VRAM, speculative decoding (which loads a second
        // drafter model onto the GPU) may fail. Fall back to disabling it and retry.
        var engine = litert_lm_engine_create(settings)
        if engine == nil && backend == .gpu {
            litert_lm_engine_settings_set_enable_speculative_decoding(settings, false)
            engine = litert_lm_engine_create(settings)
        }
        guard let engine else {
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
        sessionPtr.map { litert_lm_session_delete($0) }
        litert_lm_engine_delete(enginePtr)
    }

    /// Clears the KV cache by recreating the session.
    /// Call between independent inferences. Do not call while inference is in progress.
    public func resetSession() throws {
        sessionPtr.map { litert_lm_session_delete($0) }
        guard let newSession = litert_lm_engine_create_session(enginePtr, nil) else {
            sessionPtr = nil
            throw LiteRTError.sessionCreationFailed
        }
        sessionPtr = newSession
    }

    // MARK: - Public API

    /// Streams transcription tokens from raw PCM audio.
    /// - Parameter pcmData: Raw audio in 16 kHz, mono, Float32 format.
    /// - Returns: An `AsyncStream` that yields transcription tokens as they are generated.
    public func transcribeAudio(pcmData: Data) -> AsyncStream<String> {
        makeConversationAudioStream(pcmData: pcmData)
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
                            var inputs: [LiteRtLmInputData] = [
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeText,
                                          data: UnsafeRawPointer(prefixPtr),
                                          size: prefix.utf8.count),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeAudio,
                                          data: rawBuffer.baseAddress,
                                          size: pcmData.count),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeAudioEnd,
                                          data: nil,
                                          size: 0),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeText,
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
        print("[Conv] makeConversationAudioStream: \(pcmData.count) bytes")
        // LiteRT-LM allows only one session OR conversation at a time.
        // Release the persistent session so the conversation API can take the slot.
        sessionPtr.map { litert_lm_session_delete($0) }
        sessionPtr = nil

        return AsyncStream { continuation in
            guard let configPtr = litert_lm_conversation_config_create() else {
                print("[Conv] conversation_config_create failed")
                self.sessionPtr = litert_lm_engine_create_session(self.enginePtr, nil)
                continuation.finish()
                return
            }
            guard let convPtr = litert_lm_conversation_create(self.enginePtr, configPtr) else {
                print("[Conv] conversation_create failed")
                litert_lm_conversation_config_delete(configPtr)
                self.sessionPtr = litert_lm_engine_create_session(self.enginePtr, nil)
                continuation.finish()
                return
            }
            litert_lm_conversation_config_delete(configPtr)
            print("[Conv] conversation created, sending message (\(pcmData.count) bytes PCM)")

            let enginePtr = self.enginePtr
            let box = ConvContinuationBox(continuation, convPtr) { [weak self] in
                let newSession = litert_lm_engine_create_session(enginePtr, nil)
                self?.sessionPtr = newSession
                if newSession != nil {
                    print("[Conv] session restored after conversation")
                } else {
                    print("[Conv] ERROR: failed to restore session after conversation")
                }
            }
            let boxPtr = Unmanaged.passRetained(box).toOpaque()

            let callback: LiteRtLmStreamCallback = { boxPtr, chunk, isFinal, errorMsg in
                guard let boxPtr else { return }
                let box = Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr).takeUnretainedValue()
                if let chunk {
                    let text = String(cString: chunk)
                    if !text.isEmpty {
                        box.tokenCount += 1
                        if box.tokenCount <= 5 { print("[Conv] token #\(box.tokenCount): '\(text)'") }
                        box.continuation.yield(text)
                    }
                }
                if isFinal {
                    print("[Conv] isFinal, totalTokens=\(box.tokenCount)")
                    box.continuation.finish()
                    Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr).release()
                }
            }

            let base64Audio = pcmData.base64EncodedString()
            let messageJSON = """
            {"role":"user","content":[{"type":"audio","mime_type":"audio/pcm;rate=16000","blob":"\(base64Audio)"},{"type":"text","text":"Transcribe this audio"}]}
            """
            print("[Conv] messageJSON length: \(messageJSON.count) chars")

            let thread = Thread {
                let rc = litert_lm_conversation_send_message_stream(
                    convPtr, messageJSON, nil, callback, boxPtr)
                if rc != 0 {
                    print("[Conv] send_message_stream failed: rc=\(rc)")
                    Unmanaged<ConvContinuationBox>.fromOpaque(boxPtr)
                        .takeRetainedValue().continuation.finish()
                }
            }
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }

    private func makeInterleavedStream(pcmData: Data) -> AsyncStream<String> {
        guard let session = sessionPtr else {
            return AsyncStream { $0.finish() }
        }

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
                            var inputs: [LiteRtLmInputData] = [
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeText,
                                          data: UnsafeRawPointer(prefixPtr),
                                          size: prefix.utf8.count),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeAudio,
                                          data: rawBuffer.baseAddress,
                                          size: pcmData.count),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeAudioEnd,
                                          data: nil,
                                          size: 0),
                                LiteRtLmInputData(type: kLiteRtLmInputDataTypeText,
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
        guard let session = sessionPtr else {
            return AsyncStream { $0.finish() }
        }
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
                    var inputs: [LiteRtLmInputData] = [
                        LiteRtLmInputData(type: kLiteRtLmInputDataTypeText,
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
    var tokenCount: Int = 0
    private let onDeinit: () -> Void
    init(_ continuation: AsyncStream<String>.Continuation, _ convPtr: OpaquePointer, onDeinit: @escaping () -> Void = {}) {
        self.continuation = continuation
        self.convPtr = convPtr
        self.onDeinit = onDeinit
    }
    deinit {
        litert_lm_conversation_delete(convPtr)
        onDeinit()
    }
}
