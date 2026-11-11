//
//  OpenAICompatibleProvider.swift
//  Dear Diary
//
//  Talks to any service that speaks the OpenAI chat format, using URLSession
//  only. That is OpenAI itself, and whatever address the user gives under
//  "Other" in Settings. No SDK, no third-party code.
//
//  The same two rules as the Claude client:
//  1. Nothing is sent unless the gate says AI is on and this service is set up.
//     That check happens before any network call is made.
//  2. Nothing is logged. Not the key, not the request, not the reply.
//
//  API details were checked against OpenAI's documentation on 11 Nov 2026:
//  the chat completions request, "max_completion_tokens" replacing
//  "max_tokens", the streamed chunk format and its closing "[DONE]" line, the
//  usage chunk, refusals, "response_format" for a required JSON shape, the
//  error codes, and the model list.
//

import Foundation

final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    /// The provider the app uses. It is created the first time something asks for it.
    static let shared = OpenAICompatibleProvider(access: { AISettings.shared.endpointAccess() })

    private let access: () -> AIEndpointAccess
    private let session: URLSession

    /// Models that turned out not to accept the optional parts of a request (a required
    /// JSON shape, a ceiling on the reply), remembered until the app quits.
    private let lock = NSLock()
    private var plainOnlyModels: Set<String> = []

    init(access: @escaping () -> AIEndpointAccess, session: URLSession = AnthropicProvider.makeSession()) {
        self.access = access
        self.session = session
    }

    // MARK: - LLMProvider

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.run(request) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AnthropicProvider.normalized(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func complete(_ request: LLMRequest) async throws -> LLMReply {
        do {
            var text = ""
            let outcome = try await run(request) { piece in
                text += piece
            }
            if outcome.stopReason == "length" {
                throw LLMError.truncated
            }
            return LLMReply(text: text, inputTokens: outcome.inputTokens, outputTokens: outcome.outputTokens)
        } catch {
            throw AnthropicProvider.normalized(error)
        }
    }

    /// The models this service offers. For OpenAI, models that cannot hold a
    /// conversation (speech, images, embeddings) are left out and the newest come first.
    func models() async throws -> [AIModelChoice] {
        do {
            let endpoint = try allowedEndpoint()
            var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("models"))
            Self.sign(&urlRequest, with: endpoint)
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.unexpected
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(forStatus: http.statusCode, body: data)
            }
            return Self.modelChoices(from: data, kind: endpoint.kind)
        } catch {
            throw AnthropicProvider.normalized(error)
        }
    }

    // MARK: - Sending

    private struct Outcome {
        var stopReason: String? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
    }

    /// The gate. Throws before anything touches the network when AI is off or this service is not set up.
    private func allowedEndpoint() throws -> AIEndpoint {
        switch access() {
        case .off:
            throw LLMError.aiOff
        case .noKey:
            throw LLMError.missingKey
        case .noAddress:
            throw LLMError.missingAddress
        case .allowed(let endpoint):
            return endpoint
        }
    }

    /// Sends one request and reads the reply to its end, handing each piece of text to `onText`.
    private func run(_ request: LLMRequest, onText: (String) -> Void) async throws -> Outcome {
        let endpoint = try allowedEndpoint()
        var useExtras = !isPlainOnly(request.model)
        var (bytes, http) = try await open(request, endpoint: endpoint, extras: useExtras)

        // A model that does not accept an optional part rejects the whole request.
        // Ask once more without them, and remember if that was the cause.
        if useExtras, http.statusCode == 400 {
            useExtras = false
            (bytes, http) = try await open(request, endpoint: endpoint, extras: false)
            if (200..<300).contains(http.statusCode) {
                rememberPlainOnly(request.model)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 65_536 { break }
            }
            throw Self.error(forStatus: http.statusCode, body: body)
        }

        var outcome = Outcome()
        var finished = false
        var filter = ThinkTagFilter()

        lines: for try await line in bytes.lines {
            let chunk = OpenAIStreamParser.parse(line: line)
            if let error = chunk.error {
                throw error
            }
            if chunk.refused {
                throw LLMError.refused
            }
            if let text = chunk.text {
                let shown = filter.feed(text)
                if !shown.isEmpty { onText(shown) }
            }
            if let input = chunk.inputTokens { outcome.inputTokens = input }
            if let output = chunk.outputTokens { outcome.outputTokens = output }
            if let reason = chunk.finishReason {
                if reason == "content_filter" {
                    throw LLMError.refused
                }
                outcome.stopReason = reason
                finished = true
            }
            if chunk.isDone {
                finished = true
                break lines
            }
        }

        let rest = filter.finish()
        if !rest.isEmpty { onText(rest) }

        // A reply that stops without saying why was cut off somewhere on the way.
        guard finished else {
            throw LLMError.unexpected
        }
        return outcome
    }

    private func open(_ request: LLMRequest, endpoint: AIEndpoint, extras: Bool) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let urlRequest = try Self.makeURLRequest(for: request, endpoint: endpoint, extras: extras)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unexpected
        }
        return (bytes, http)
    }

    /// Builds the request. With `extras` on it carries a ceiling on the reply and, when
    /// the request asks for one, a required JSON shape.
    static func makeURLRequest(for request: LLMRequest, endpoint: AIEndpoint, extras: Bool) throws -> URLRequest {
        var messages: [[String: Any]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }

        var body: [String: Any] = [
            "model": request.model,
            "messages": messages,
            "stream": true,
        ]
        if endpoint.kind == .openai {
            // Ask for token counts at the end of the stream.
            body["stream_options"] = ["include_usage": true]
        }
        // The shape goes in as its own text, so its fields keep the order they are written in.
        let slot = SchemaSlot()
        let shape = extras ? request.jsonSchema : nil
        if extras {
            // OpenAI's own name for the ceiling is the newer one; other services still use the older.
            body[endpoint.kind == .openai ? "max_completion_tokens" : "max_tokens"] = request.maxTokens
            if shape != nil {
                body["response_format"] = [
                    "type": "json_schema",
                    "json_schema": ["name": "reply", "strict": true, "schema": slot.placeholder],
                ]
            }
        }

        var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        sign(&urlRequest, with: endpoint)
        urlRequest.httpBody = slot.fill(try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), with: shape)
        return urlRequest
    }

    private static func sign(_ urlRequest: inout URLRequest, with endpoint: AIEndpoint) {
        if let key = endpoint.apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Optional parts a model may not accept

    private func isPlainOnly(_ model: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return plainOnlyModels.contains(model)
    }

    private func rememberPlainOnly(_ model: String) {
        lock.lock()
        plainOnlyModels.insert(model)
        lock.unlock()
    }

    // MARK: - Turning failures into plain errors

    /// An error response that arrived with an HTTP status code.
    static func error(forStatus status: Int, body: Data) -> LLMError {
        let detail = errorDetail(in: body)
        switch status {
        case 401:
            return .invalidKey
        case 402:
            return .billing
        case 403:
            return .permission
        case 404:
            return .modelNotFound
        case 429:
            return isAboutMoney(detail) ? .billing : .rateLimited
        case 503:
            return .overloaded
        case 400..<500:
            return .rejected(detail: String(detail.message.prefix(200)))
        case 500..<600:
            return .server
        default:
            return .unexpected
        }
    }

    /// Running out of credit and hitting a spending limit both arrive as "too many requests".
    private static func isAboutMoney(_ detail: (message: String, type: String, code: String)) -> Bool {
        let marks = ["insufficient_quota", "credit_balance_exhausted", "spend_limit"]
        return marks.contains { detail.type.contains($0) || detail.code.contains($0) }
    }

    /// Reads {"error": {"message", "type", "code"}} and also the plainer {"error": "..."} some services send.
    static func errorDetail(in body: Data) -> (message: String, type: String, code: String) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return ("", "", "")
        }
        if let text = object["error"] as? String {
            return (text, "", "")
        }
        let error = object["error"] as? [String: Any] ?? [:]
        return (
            error["message"] as? String ?? "",
            error["type"] as? String ?? "",
            error["code"] as? String ?? ""
        )
    }

    // MARK: - The model list

    /// Words in a model's name that mean it cannot hold a written conversation.
    private static let notForConversation = [
        "embedding", "tts", "whisper", "dall-e", "image", "audio", "realtime", "transcribe", "moderation", "sora",
    ]

    static func modelChoices(from data: Data, kind: AIProviderKind) -> [AIModelChoice] {
        struct List: Decodable {
            struct Model: Decodable {
                let id: String
                let created: Double?
            }

            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            return []
        }
        var models = list.data
        if kind == .openai {
            models = models
                .filter { model in !notForConversation.contains { model.id.lowercased().contains($0) } }
                .sorted { ($0.created ?? 0, $1.id) > ($1.created ?? 0, $0.id) }
        } else {
            models.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
        return models.map { AIModelChoice(id: $0.id, name: $0.id) }
    }
}

// MARK: - Reading the stream

/// What one line of a streamed reply carries.
struct OpenAIStreamChunk: Equatable {
    /// A piece of the reply text.
    var text: String? = nil
    /// True when the model declined to answer.
    var refused = false
    /// Why the model stopped: "stop", "length" or "content_filter".
    var finishReason: String? = nil
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    /// A problem reported part-way through.
    var error: LLMError? = nil
    /// True for the closing "[DONE]" line.
    var isDone = false
}

enum OpenAIStreamParser {
    /// Reads one line of the server-sent event stream. Each chunk's JSON arrives on a
    /// single line that starts with "data:". Anything else (blank lines, comments) carries nothing.
    static func parse(line: String) -> OpenAIStreamChunk {
        var chunk = OpenAIStreamChunk()
        guard line.hasPrefix("data:") else {
            return chunk
        }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            chunk.isDone = true
            return chunk
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return chunk
        }

        if object["error"] != nil {
            let detail = OpenAICompatibleProvider.errorDetail(in: data)
            switch detail.type {
            case "rate_limit_error", "rate_limit_exceeded":
                chunk.error = .rateLimited
            case "service_unavailable_error":
                chunk.error = .overloaded
            case "invalid_request_error":
                chunk.error = .rejected(detail: String(detail.message.prefix(200)))
            default:
                chunk.error = .server
            }
            return chunk
        }

        if let choice = (object["choices"] as? [[String: Any]])?.first {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let text = delta["content"] as? String, !text.isEmpty {
                chunk.text = text
            }
            if let refusal = delta["refusal"] as? String, !refusal.isEmpty {
                chunk.refused = true
            }
            if let reason = choice["finish_reason"] as? String {
                chunk.finishReason = reason
            }
        }
        if let usage = object["usage"] as? [String: Any] {
            chunk.inputTokens = usage["prompt_tokens"] as? Int
            chunk.outputTokens = usage["completion_tokens"] as? Int
        }
        return chunk
    }
}
