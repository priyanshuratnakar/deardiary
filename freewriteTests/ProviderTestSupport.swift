//
//  ProviderTestSupport.swift
//  freewriteTests
//
//  Helpers for the tests of the services other than Claude: throwaway
//  settings with their own Keychain items, and made-up replies in the shapes
//  OpenAI's and Ollama's documentation show.
//

import Foundation
@testable import freewrite

/// Throwaway settings: their own preferences and their own Keychain items, removed afterwards.
final class SettingsBox {
    let suiteName = "deardiary.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let keychain: Keychain

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        keychain = Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString).anthropic-api-key", account: "test")
    }

    /// A fresh reading of the saved settings, as the app would make at launch.
    func settings() -> AISettings {
        AISettings(defaults: defaults, keychain: keychain)
    }

    deinit {
        keychain.delete()
        keychain.sibling(named: "openai-api-key").delete()
        keychain.sibling(named: "other-api-key").delete()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

enum ProviderFixtures {
    static func body(of request: URLRequest) -> [String: Any] {
        guard let data = request.httpBody ?? request.httpBodyStream.map(read),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    // MARK: - OpenAI chat format

    /// A streamed reply: a first chunk with only the role, "Hello!" in two pieces,
    /// the reason it stopped, the token counts, then the closing line.
    static let openAIHello = """
    data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}],"usage":null}

    data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"Hel"},"finish_reason":null}],"usage":null}

    data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{"content":"lo!"},"finish_reason":null}],"usage":null}

    data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":null}

    data: {"id":"c1","object":"chat.completion.chunk","created":1,"model":"test-model","choices":[],"usage":{"prompt_tokens":25,"completion_tokens":7,"total_tokens":32}}

    data: [DONE]

    """

    static func openAIStream(pieces: [String], finishReason: String = "stop", done: Bool = true) -> String {
        var lines = pieces.map { piece -> String in
            let text = String(data: try! JSONSerialization.data(withJSONObject: [piece]), encoding: .utf8)!.dropFirst().dropLast()
            return "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\(text)},\"finish_reason\":null}]}\n"
        }
        lines.append("data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(finishReason)\"}]}\n")
        if done { lines.append("data: [DONE]\n") }
        return lines.joined(separator: "\n")
    }

    static let openAIRefusal = """
    data: {"choices":[{"index":0,"delta":{"role":"assistant","refusal":"I can't help with that."},"finish_reason":null}]}

    data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

    data: [DONE]

    """

    static func openAIError(message: String, type: String = "invalid_request_error", code: String? = nil) -> String {
        let codeText = code.map { "\"\($0)\"" } ?? "null"
        return "{\"error\":{\"message\":\"\(message)\",\"type\":\"\(type)\",\"param\":null,\"code\":\(codeText)}}"
    }

    static let openAIModels = """
    {"object":"list","data":[
      {"id":"older-chat-model","object":"model","created":1700000000,"owned_by":"openai"},
      {"id":"text-embedding-test","object":"model","created":1720000000,"owned_by":"openai"},
      {"id":"newer-chat-model","object":"model","created":1750000000,"owned_by":"openai"},
      {"id":"tts-test","object":"model","created":1760000000,"owned_by":"openai"},
      {"id":"whisper-test","object":"model","created":1690000000,"owned_by":"openai"}
    ]}
    """

    // MARK: - Ollama

    /// A streamed reply: one JSON object per line, private thinking first, then "Hello!" in two pieces.
    static let ollamaHello = """
    {"model":"test-model","created_at":"2026-11-11T08:00:00Z","message":{"role":"assistant","content":"","thinking":"They said hello."},"done":false}
    {"model":"test-model","created_at":"2026-11-11T08:00:00Z","message":{"role":"assistant","content":"Hel"},"done":false}
    {"model":"test-model","created_at":"2026-11-11T08:00:01Z","message":{"role":"assistant","content":"lo!"},"done":false}
    {"model":"test-model","created_at":"2026-11-11T08:00:01Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":25,"eval_count":7}

    """

    static func ollamaStream(pieces: [String], doneReason: String? = "stop") -> String {
        var lines = pieces.map { piece -> String in
            let text = String(data: try! JSONSerialization.data(withJSONObject: [piece]), encoding: .utf8)!.dropFirst().dropLast()
            return "{\"message\":{\"role\":\"assistant\",\"content\":\(text)},\"done\":false}"
        }
        if let doneReason {
            lines.append("{\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"done\":true,\"done_reason\":\"\(doneReason)\"}")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let ollamaTags = """
    {"models":[
      {"name":"qwen-test:8b","model":"qwen-test:8b","size":5000000000,"details":{"format":"gguf","family":"qwen","parameter_size":"8.2B","quantization_level":"Q4_K_M"}},
      {"name":"gemma-test","model":"gemma-test","size":3000000000,"details":{"format":"gguf","family":"gemma","parameter_size":"4.3B","quantization_level":"Q4_K_M"}}
    ]}
    """

    // MARK: - Claude's model list

    static let claudeModels = """
    {"data":[
      {"type":"model","id":"claude-newest-test","display_name":"Claude Newest","created_at":"2026-09-21T00:00:00Z","lifecycle":"active"},
      {"type":"model","id":"claude-small-test","display_name":"Claude Small","created_at":"2026-06-01T00:00:00Z","lifecycle":"active"},
      {"type":"model","id":"claude-old-test","display_name":"Claude Old","created_at":"2025-01-01T00:00:00Z","lifecycle":"deprecated"}
    ],"first_id":"claude-newest-test","has_more":false,"last_id":"claude-old-test"}
    """
}
