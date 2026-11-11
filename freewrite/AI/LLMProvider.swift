//
//  LLMProvider.swift
//  Dear Diary
//
//  A small, provider-neutral way to ask an AI model for text. Three clients
//  follow this protocol: Claude (AnthropicProvider), anything that speaks the
//  OpenAI chat format (OpenAICompatibleProvider) and a model on this Mac
//  (OllamaProvider). AIRouter sends each request to the one chosen in Settings.
//

import Foundation

struct LLMMessage: Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

struct LLMRequest {
    /// The model name, always taken from Settings.
    var model: String
    /// Instructions for the model, kept separate from the conversation.
    var system: String? = nil
    /// The conversation so far, oldest first.
    var messages: [LLMMessage]
    /// The most the model may write in its reply.
    var maxTokens: Int
    /// If the model's safety checks decline the request, ask the service to try
    /// once more on another of its models before giving up.
    var retryIfDeclined: Bool = false
    /// When set, the reply must be JSON in this shape (a JSON schema, as bytes).
    var jsonSchema: Data? = nil
}

/// A whole reply, with how much it used.
struct LLMReply: Equatable {
    let text: String
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
}

protocol LLMProvider {
    /// Sends the request and hands back the reply piece by piece as it is written.
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>

    /// Sends the request and returns the whole reply at once.
    /// Used for background work that needs a complete answer, such as building memory.
    func complete(_ request: LLMRequest) async throws -> LLMReply
}

/// Everything that can go wrong when asking for a reply, in terms the app can
/// show to the user. None of these ever carry entry text or the API key.
enum LLMError: Error, Equatable {
    case aiOff
    case missingKey
    /// "Other" is chosen but no address has been given.
    case missingAddress
    /// No model has been chosen for this service yet.
    case missingModel
    case invalidKey
    case billing
    case permission
    case modelNotFound
    case rateLimited
    case overloaded
    case offline
    case refused
    case truncated
    case rejected(detail: String)
    case server
    case unexpected

    /// The message as it reads when Claude is the service. Kept for the places that only ever use Claude.
    var userMessage: String {
        userMessage(for: .claude)
    }

    /// A short, plain sentence for the talk column, the map or Settings, naming the service in use.
    func userMessage(for kind: AIProviderKind) -> String {
        let service = kind.serviceName
        switch self {
        case .aiOff:
            return "AI is off. Turn it on in Settings to use this."
        case .missingKey:
            return "No API key yet. Add one in Settings."
        case .missingAddress:
            return "No address yet. Add one in Settings."
        case .missingModel:
            return "No model chosen yet. Pick one in Settings."
        case .invalidKey:
            return "\(service) didn't accept that API key. Check it and save it again."
        case .billing:
            return kind.accountName.map { "There's a billing problem on your \($0) account. Check your credits there." }
                ?? "There's a billing problem on your account with that service. Check your credits there."
        case .permission:
            return kind.accountName.map { "Your API key isn't allowed to do that. Check your \($0) account." }
                ?? "Your API key isn't allowed to do that. Check your account with that service."
        case .modelNotFound:
            return kind == .local
                ? "That model isn't on this Mac any more. Pick another in Settings."
                : "That model name wasn't found, or your account can't use it. Check the model in Settings."
        case .rateLimited:
            return "You've reached a usage limit for now. Try again in a little while."
        case .overloaded:
            return "\(service) is busy right now. Try again in a moment."
        case .offline:
            switch kind {
            case .local:
                return "Couldn't reach Ollama. Open the Ollama app, then try again."
            case .other:
                return "Couldn't reach the AI service. Check the address in Settings and your connection."
            case .claude, .openai:
                return "Couldn't reach \(service). Check your internet connection."
            }
        case .refused:
            return "\(service) declined to respond to this."
        case .truncated:
            return "The reply was cut off before it finished. Try again."
        case .rejected(let detail):
            return detail.isEmpty
                ? "\(service) couldn't accept that request."
                : "\(service) couldn't accept that request: \(detail)"
        case .server:
            return kind == .local
                ? "Something went wrong in Ollama. Try again in a moment."
                : "Something went wrong on \(kind.serviceNameInline)'s side. Try again in a moment."
        case .unexpected:
            return "Something unexpected went wrong. Try again."
        }
    }
}

/// One model a service offers, for the pickers in Settings.
struct AIModelChoice: Equatable, Identifiable {
    /// The name sent to the service.
    let id: String
    /// The name shown in Settings.
    let name: String
    /// A short extra, such as the size of a model on this Mac ("8.0B").
    var detail: String? = nil
}

/// Sends each request to whichever service is chosen in Settings.
/// Talk, memory and the connection test all go through this.
struct AIRouter: LLMProvider {
    static let shared = AIRouter(
        kind: { AISettings.shared.savedProvider() },
        claude: { AnthropicProvider.shared },
        openAIStyle: { OpenAICompatibleProvider.shared },
        local: { OllamaProvider.shared }
    )

    let kind: () -> AIProviderKind
    let claude: () -> LLMProvider
    let openAIStyle: () -> LLMProvider
    let local: () -> LLMProvider

    private func provider() -> LLMProvider {
        switch kind() {
        case .claude: return claude()
        case .openai, .other: return openAIStyle()
        case .local: return local()
        }
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        guard !request.model.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.missingModel) }
        }
        return provider().stream(request)
    }

    func complete(_ request: LLMRequest) async throws -> LLMReply {
        guard !request.model.isEmpty else {
            throw LLMError.missingModel
        }
        return try await provider().complete(request)
    }

    /// The models the chosen service offers, newest or most relevant first.
    func models() async throws -> [AIModelChoice] {
        switch kind() {
        case .claude: return try await AnthropicProvider.shared.models()
        case .openai, .other: return try await OpenAICompatibleProvider.shared.models()
        case .local: return try await OllamaProvider.shared.models()
        }
    }
}

/// Removes a model's private thinking when it arrives mixed into the reply as
/// <think>…</think>, which some open models do. Text is fed in pieces as it
/// streams, so a tag split across two pieces is handled too.
struct ThinkTagFilter {
    private static let open = "<think>"
    private static let close = "</think>"

    private var pending = ""
    private var inside = false
    private var hasEmitted = false

    /// Takes the next piece and returns what may be shown so far.
    mutating func feed(_ piece: String) -> String {
        pending += piece
        var output = ""

        while true {
            if inside {
                if let end = pending.range(of: Self.close) {
                    pending = String(pending[end.upperBound...])
                    inside = false
                    continue
                }
                // Keep only what could be the start of the closing tag.
                pending = Self.partialSuffix(of: pending, matching: Self.close)
                break
            }
            if let start = pending.range(of: Self.open) {
                output += pending[..<start.lowerBound]
                pending = String(pending[start.upperBound...])
                inside = true
                continue
            }
            let held = Self.partialSuffix(of: pending, matching: Self.open)
            output += pending.dropLast(held.count)
            pending = held
            break
        }
        return release(output)
    }

    /// Call when the reply has ended: returns anything still held back.
    mutating func finish() -> String {
        let rest = inside ? "" : pending
        pending = ""
        return release(rest)
    }

    /// Blank space before the first visible words (left behind by a thinking block) is dropped.
    private mutating func release(_ text: String) -> String {
        guard !hasEmitted else { return text }
        let trimmed = String(text.drop(while: { $0.isWhitespace }))
        if !trimmed.isEmpty {
            hasEmitted = true
        }
        return trimmed
    }

    /// The longest ending of `text` that is also a beginning of `tag` (but not all of it).
    private static func partialSuffix(of text: String, matching tag: String) -> String {
        var length = min(text.count, tag.count - 1)
        while length > 0 {
            let suffix = String(text.suffix(length))
            if tag.hasPrefix(suffix) {
                return suffix
            }
            length -= 1
        }
        return ""
    }
}

/// Puts a required reply shape (a JSON schema) into a request exactly as it is written.
///
/// A model writes its reply in the order the shape lists its fields. The shapes in this app
/// are written in the order that makes sense to fill in: the name of a thought before its
/// kind, what an entry is about before the details. The clients build their requests as
/// dictionaries and write them out with sorted keys, which used to sort the shape too, at
/// every level, so a model had to give a thought's other names and kind before its name.
/// A capable local model (gemma4:12b) never finished such a reply; a small one returned
/// thin notes. Found on 12 Nov 2026 by replaying the app's exact request.
///
/// So the shape is not passed through a dictionary at all. A client puts `placeholder`
/// where the shape belongs, writes the request out, and `fill` swaps the shape's own text in.
struct SchemaSlot {
    /// Different for every request, so nothing a person wrote can be mistaken for it.
    let placeholder = "schema-slot-" + UUID().uuidString

    /// The request body with the shape's own text where the placeholder stood.
    /// With no shape, or if the placeholder is not there, the body is returned as it is.
    func fill(_ body: Data, with schema: Data?) -> Data {
        guard let schema,
              let text = String(data: body, encoding: .utf8),
              let shape = String(data: schema, encoding: .utf8) else {
            return body
        }
        let quoted = "\"\(placeholder)\""
        guard text.contains(quoted) else { return body }
        return Data(text.replacingOccurrences(of: quoted, with: shape).utf8)
    }
}
