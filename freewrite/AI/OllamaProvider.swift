//
//  OllamaProvider.swift
//  Dear Diary
//
//  Talks to an open model running on this Mac through Ollama, a free app the
//  user installs themselves. Requests go to http://localhost:11434 and never
//  leave the Mac. URLSession only: no SDK, no third-party code.
//
//  The same two rules as the other clients:
//  1. Nothing is sent unless AI is on and "On this Mac" is chosen.
//  2. Nothing is logged.
//
//  It uses Ollama's own chat format rather than its OpenAI-style one, because
//  only this one can ask for enough room to read an entry with its memory:
//  Ollama's default is about 4,000 tokens, which would silently cut text off.
//
//  API details were checked against https://docs.ollama.com on 11 Nov 2026:
//  the chat request ("format" for a required JSON shape, "options.num_ctx"
//  and "options.num_predict"), the streamed reply (one JSON object per line,
//  "message.content", "message.thinking", "done", "done_reason"), errors
//  ({"error": "..."}, also part-way through a stream) and the list of
//  installed models.
//
//  Two settings were added on 12 Nov 2026 after trying real models on made-up
//  entries (see docs/research/model-comparison.md):
//
//  - "think": false, on every request. Newer open models think before they
//    answer unless told not to. Left to itself, gemma4:12b spent a whole
//    request thinking and returned nothing at all for memory, 18 times out of
//    18, and in talk it left 8 replies out of 13 empty after about 20 seconds
//    each. With thinking off it was complete and took about a second. A model
//    that cannot think accepts the setting and ignores it.
//  - "options.temperature": 0, when the reply must be JSON. Reading an entry
//    for memory is copying, not writing: quotes came back word for word more
//    often (83% to 96% on a small model), and the same entry gives the same
//    notes. Talk keeps each model's own setting.
//

import Foundation

final class OllamaProvider: LLMProvider, @unchecked Sendable {
    /// The provider the app uses. It is created the first time something asks for it.
    static let shared = OllamaProvider(isAllowed: { AISettings.shared.localAccess() })

    private let isAllowed: () -> Bool
    private let base: URL
    private let session: URLSession

    /// Models that turned out not to accept a required JSON shape, remembered until the app quits.
    private let lock = NSLock()
    private var plainOnlyModels: Set<String> = []

    init(
        isAllowed: @escaping () -> Bool,
        base: URL = AISettings.localBaseURL,
        session: URLSession = OllamaProvider.makeSession()
    ) {
        self.isAllowed = isAllowed
        self.base = base
        self.session = session
    }

    /// Like the other clients' session, but more patient: a model can take a while
    /// to load into memory before its first word.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 1800
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

    /// The models installed in Ollama on this Mac, by name.
    func models() async throws -> [AIModelChoice] {
        do {
            try checkAllowed()
            let (data, response) = try await session.data(from: base.appendingPathComponent("api/tags"))
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.unexpected
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(forStatus: http.statusCode, body: data)
            }
            return Self.modelChoices(from: data)
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

    /// The gate. Throws before anything touches the network when AI is off.
    private func checkAllowed() throws {
        guard isAllowed() else {
            throw LLMError.aiOff
        }
    }

    private func run(_ request: LLMRequest, onText: (String) -> Void) async throws -> Outcome {
        try checkAllowed()
        var useSchema = request.jsonSchema != nil && !isPlainOnly(request.model)
        var (bytes, http) = try await open(request, schema: useSchema)

        // A model that cannot follow a required shape rejects the request. Ask once more without it.
        if useSchema, http.statusCode == 400 {
            useSchema = false
            (bytes, http) = try await open(request, schema: false)
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
            switch OllamaStreamParser.parse(line: line) {
            case .text(let piece):
                let shown = filter.feed(piece)
                if !shown.isEmpty { onText(shown) }
            case .failed:
                throw LLMError.server
            case .finished(let reason, let input, let output):
                outcome = Outcome(stopReason: reason, inputTokens: input, outputTokens: output)
                finished = true
                break lines
            case .ignored:
                continue
            }
        }

        let rest = filter.finish()
        if !rest.isEmpty { onText(rest) }

        // A reply that stops without its closing line was cut off somewhere on the way.
        guard finished else {
            throw LLMError.unexpected
        }
        return outcome
    }

    private func open(_ request: LLMRequest, schema: Bool) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let urlRequest = try Self.makeURLRequest(for: request, base: base, schema: schema)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unexpected
        }
        return (bytes, http)
    }

    /// Builds the request. With `schema` on, a required JSON shape is included when the request asks for one.
    static func makeURLRequest(for request: LLMRequest, base: URL, schema: Bool) throws -> URLRequest {
        var messages: [[String: Any]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }

        var options: [String: Any] = [
            // Room to read an entry together with its memory, and a ceiling on the reply.
            "num_ctx": AILimits.localContextTokens,
            "num_predict": request.maxTokens,
        ]
        if request.jsonSchema != nil {
            // The reply is notes copied from an entry, so it should not vary from one try to the next.
            options["temperature"] = 0
        }

        var body: [String: Any] = [
            "model": request.model,
            "messages": messages,
            "stream": true,
            "options": options,
            // Answer straight away, without a private thinking step first.
            "think": false,
        ]
        // The shape goes in as its own text, so its fields keep the order they are written in.
        let slot = SchemaSlot()
        let shape = schema ? request.jsonSchema : nil
        if shape != nil {
            body["format"] = slot.placeholder
        }

        var urlRequest = URLRequest(url: base.appendingPathComponent("api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = slot.fill(try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), with: shape)
        return urlRequest
    }

    // MARK: - A required shape a model may not accept

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

    static func error(forStatus status: Int, body: Data) -> LLMError {
        let detail = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String ?? ""
        switch status {
        case 404:
            return .modelNotFound
        case 429:
            return .rateLimited
        case 400..<500:
            return .rejected(detail: String(detail.prefix(200)))
        case 500..<600:
            return .server
        default:
            return .unexpected
        }
    }

    // MARK: - The model list

    static func modelChoices(from data: Data) -> [AIModelChoice] {
        struct Tags: Decodable {
            struct Model: Decodable {
                struct Details: Decodable {
                    let parameter_size: String?
                }

                let name: String
                let details: Details?
            }

            let models: [Model]
        }
        guard let tags = try? JSONDecoder().decode(Tags.self, from: data) else {
            return []
        }
        return tags.models
            .map { AIModelChoice(id: $0.name, name: $0.name, detail: $0.details?.parameter_size) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Reading the stream

/// What one line of a streamed reply means to the app.
enum OllamaStreamEvent: Equatable {
    /// A piece of the reply text.
    case text(String)
    /// Ollama reported a problem part-way through.
    case failed
    /// The reply is complete, with why it stopped ("stop" or "length") and how much it used.
    case finished(reason: String?, inputTokens: Int?, outputTokens: Int?)
    /// Anything else, including a thinking model's private thinking, which arrives
    /// separately from the reply and is never shown.
    case ignored
}

enum OllamaStreamParser {
    /// Reads one line of the reply. Each line is one JSON object.
    static func parse(line: String) -> OllamaStreamEvent {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored
        }
        if object["error"] != nil {
            return .failed
        }
        if object["done"] as? Bool == true {
            return .finished(
                reason: object["done_reason"] as? String,
                inputTokens: object["prompt_eval_count"] as? Int,
                outputTokens: object["eval_count"] as? Int
            )
        }
        if let text = (object["message"] as? [String: Any])?["content"] as? String, !text.isEmpty {
            return .text(text)
        }
        return .ignored
    }
}
