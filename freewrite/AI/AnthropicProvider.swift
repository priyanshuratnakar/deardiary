//
//  AnthropicProvider.swift
//  Dear Diary
//
//  Talks to Claude through Anthropic's Messages API using URLSession only.
//  No SDK, no third-party code.
//
//  Two rules this file enforces:
//  1. Nothing is sent unless `access()` says AI is on and a key exists.
//     That check happens before any network call is made.
//  2. Nothing is logged. Not the key, not the request, not the reply.
//
//  API details were checked against https://docs.claude.com on 10 Nov 2026:
//  endpoint, headers, API version, streaming event format, error shapes, how
//  declined replies and the server-side retry ("fallbacks") behave, and how to
//  ask for JSON in a fixed shape ("output_config.format").
//

import Foundation

final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The list of models, newest first. Checked against the docs on 11 Nov 2026.
    static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=100")!
    static let apiVersion = "2026-10-21"

    /// Turns on Anthropic's server-side retry: if a model's safety checks decline a
    /// request, the service runs it again on the model it recommends instead.
    /// The app never names that other model; the service chooses it.
    static let declineRetryBeta = "server-side-fallback-2026-07-01"

    /// The provider the app uses. It is created the first time something asks for it.
    static let shared = AnthropicProvider(access: { AISettings.shared.access() })

    private let access: () -> AIAccess
    private let session: URLSession

    /// Models that turned out not to accept the optional features (the retry on decline,
    /// a required JSON shape), remembered until the app quits so later requests skip them.
    private let lock = NSLock()
    private var plainOnlyModels: Set<String> = []

    init(access: @escaping () -> AIAccess, session: URLSession = AnthropicProvider.makeSession()) {
        self.access = access
        self.session = session
    }

    /// A session that keeps nothing on disk: no cache, no cookies.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
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
                    continuation.finish(throwing: Self.normalized(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// The whole reply at once. It is still fetched as a stream underneath, so a
    /// long answer cannot time out while the model is thinking.
    func complete(_ request: LLMRequest) async throws -> LLMReply {
        do {
            var text = ""
            let outcome = try await run(request) { piece in
                text += piece
            }
            if outcome.stopReason == "max_tokens" {
                throw LLMError.truncated
            }
            return LLMReply(text: text, inputTokens: outcome.inputTokens, outputTokens: outcome.outputTokens)
        } catch {
            throw Self.normalized(error)
        }
    }

    /// The Claude models this key can use, newest first, by the names Anthropic gives them.
    /// Models that have been retired or are on their way out are left off.
    func models() async throws -> [AIModelChoice] {
        do {
            let apiKey: String
            switch access() {
            case .off:
                throw LLMError.aiOff
            case .noKey:
                throw LLMError.missingKey
            case .allowed(let key):
                apiKey = key
            }
            var urlRequest = URLRequest(url: Self.modelsEndpoint)
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.unexpected
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(forStatus: http.statusCode, body: data)
            }
            return Self.modelChoices(from: data)
        } catch {
            throw Self.normalized(error)
        }
    }

    static func modelChoices(from data: Data) -> [AIModelChoice] {
        struct List: Decodable {
            struct Model: Decodable {
                let id: String
                let display_name: String?
                let lifecycle: String?
            }

            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            return []
        }
        return list.data
            .filter { $0.lifecycle == nil || $0.lifecycle == "active" }
            .map { AIModelChoice(id: $0.id, name: $0.display_name ?? $0.id) }
    }

    // MARK: - Sending

    private struct Outcome {
        var stopReason: String? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
    }

    /// Sends one request and reads the reply to its end, handing each piece of text to `onText`.
    private func run(_ request: LLMRequest, onText: (String) -> Void) async throws -> Outcome {
        var useExtras = shouldUseExtras(for: request)
        var (bytes, http) = try await open(request, extras: useExtras)

        // A model that does not accept an optional feature rejects the whole request.
        // Ask once more without them, and remember if that was the cause.
        if useExtras, http.statusCode == 400 {
            useExtras = false
            (bytes, http) = try await open(request, extras: false)
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

        lines: for try await line in bytes.lines {
            if let usage = AnthropicStreamParser.usage(line: line) {
                outcome.inputTokens = usage.input ?? outcome.inputTokens
                outcome.outputTokens = usage.output ?? outcome.outputTokens
            }
            switch AnthropicStreamParser.parse(line: line) {
            case .text(let piece):
                onText(piece)
            case .stopped(let reason):
                if reason == "refusal" {
                    throw LLMError.refused
                }
                outcome.stopReason = reason
            case .failed(let errorType):
                throw Self.error(forErrorType: errorType)
            case .finished:
                finished = true
                break lines
            case .ignored:
                continue
            }
        }

        // A reply that stops without its closing event was cut off somewhere on the way.
        guard finished else {
            throw LLMError.unexpected
        }
        return outcome
    }

    private func open(_ request: LLMRequest, extras: Bool) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let urlRequest = try authorizedRequest(for: request, extras: extras)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unexpected
        }
        return (bytes, http)
    }

    /// The gate. Throws before anything touches the network when AI is off or there is no key.
    private func authorizedRequest(for request: LLMRequest, extras: Bool) throws -> URLRequest {
        switch access() {
        case .off:
            throw LLMError.aiOff
        case .noKey:
            throw LLMError.missingKey
        case .allowed(let apiKey):
            return try Self.makeURLRequest(for: request, apiKey: apiKey, stream: true, extras: extras)
        }
    }

    /// Builds the request. With `extras` on, the optional features the request asks for
    /// are included: the retry on another model if declined, and a required JSON shape.
    static func makeURLRequest(for request: LLMRequest, apiKey: String, stream: Bool, extras: Bool = false) throws -> URLRequest {
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = system
        }
        if stream {
            body["stream"] = true
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        if extras {
            if request.retryIfDeclined {
                body["fallbacks"] = "default"
                urlRequest.setValue(declineRetryBeta, forHTTPHeaderField: "anthropic-beta")
            }
            if let schemaData = request.jsonSchema {
                let schema = try JSONSerialization.jsonObject(with: schemaData)
                body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return urlRequest
    }

    // MARK: - Optional features a model may not accept

    private func shouldUseExtras(for request: LLMRequest) -> Bool {
        guard request.retryIfDeclined || request.jsonSchema != nil else { return false }
        lock.lock()
        defer { lock.unlock() }
        return !plainOnlyModels.contains(request.model)
    }

    private func rememberPlainOnly(_ model: String) {
        lock.lock()
        plainOnlyModels.insert(model)
        lock.unlock()
    }

    // MARK: - Turning failures into plain errors

    /// An error response that arrived with an HTTP status code.
    static func error(forStatus status: Int, body: Data) -> LLMError {
        let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error.message ?? ""
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
            return .rateLimited
        case 529:
            return .overloaded
        case 400..<500:
            return .rejected(detail: String(detail.prefix(200)))
        case 500..<600:
            return .server
        default:
            return .unexpected
        }
    }

    /// An error that arrived part-way through a streamed reply.
    static func error(forErrorType errorType: String) -> LLMError {
        switch errorType {
        case "overloaded_error":
            return .overloaded
        case "rate_limit_error":
            return .rateLimited
        case "authentication_error":
            return .invalidKey
        case "billing_error":
            return .billing
        case "permission_error":
            return .permission
        case "not_found_error":
            return .modelNotFound
        case "invalid_request_error", "request_too_large":
            return .rejected(detail: "")
        default:
            return .server
        }
    }

    /// Makes sure callers only ever see `LLMError` or a cancellation.
    static func normalized(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        if let known = error as? LLMError {
            return known
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? CancellationError() : LLMError.offline
        }
        return LLMError.unexpected
    }

    // MARK: - Wire formats

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }

        let error: Detail
    }
}

// MARK: - Reading the stream

/// What one line of a streamed reply means to the app.
enum AnthropicStreamEvent: Equatable {
    /// A piece of the reply text.
    case text(String)
    /// The model said why it stopped (for example "end_turn" or "refusal").
    case stopped(reason: String)
    /// The service reported a problem part-way through.
    case failed(errorType: String)
    /// The reply is complete.
    case finished
    /// Anything else: keep-alive pings, thinking, event names, the marker left when
    /// another model takes over after a decline, and event types added in future.
    /// These are skipped on purpose.
    case ignored
}

enum AnthropicStreamParser {
    /// Reads one line of the server-sent event stream.
    /// Each event's JSON arrives on a single line that starts with "data:".
    static func parse(line: String) -> AnthropicStreamEvent {
        guard line.hasPrefix("data:") else {
            return .ignored
        }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .ignored
        }

        switch payload.type {
        case "content_block_delta":
            if payload.delta?.type == "text_delta", let text = payload.delta?.text, !text.isEmpty {
                return .text(text)
            }
            return .ignored
        case "message_delta":
            if let reason = payload.delta?.stop_reason {
                return .stopped(reason: reason)
            }
            return .ignored
        case "message_stop":
            return .finished
        case "error":
            return .failed(errorType: payload.error?.type ?? "api_error")
        default:
            return .ignored
        }
    }

    /// Token counts, when a line carries them: what was sent arrives at the start,
    /// what was written arrives at the end.
    static func usage(line: String) -> (input: Int?, output: Int?)? {
        guard line.hasPrefix("data:"), line.contains("\"usage\"") else {
            return nil
        }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(UsagePayload.self, from: data) else {
            return nil
        }
        let usage = payload.usage ?? payload.message?.usage
        guard usage?.input_tokens != nil || usage?.output_tokens != nil else {
            return nil
        }
        return (usage?.input_tokens, payload.type == "message_start" ? nil : usage?.output_tokens)
    }

    private struct UsagePayload: Decodable {
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
        }

        struct Message: Decodable {
            let usage: Usage?
        }

        let type: String
        let usage: Usage?
        let message: Message?
    }

    private struct Payload: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stop_reason: String?
        }

        struct ErrorDetail: Decodable {
            let type: String?
        }

        let type: String
        let delta: Delta?
        let error: ErrorDetail?
    }
}
