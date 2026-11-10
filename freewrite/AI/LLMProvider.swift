//
//  LLMProvider.swift
//  Dear Diary
//
//  A small, provider-neutral way to ask an AI model for text. Claude is the
//  only provider today; others can be added later by writing another type
//  that follows this protocol.
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

    /// A short, plain sentence for the talk column, the map or Settings.
    var userMessage: String {
        switch self {
        case .aiOff:
            return "AI is off. Turn it on in Settings to use this."
        case .missingKey:
            return "No API key yet. Add one in Settings."
        case .invalidKey:
            return "Claude didn't accept that API key. Check it and save it again."
        case .billing:
            return "There's a billing problem on your Anthropic account."
        case .permission:
            return "Your API key isn't allowed to do that. Check your Anthropic account."
        case .modelNotFound:
            return "That model name wasn't found, or your account can't use it. Check the model in Settings."
        case .rateLimited:
            return "You've reached a usage limit for now. Try again in a little while."
        case .overloaded:
            return "Claude is busy right now. Try again in a moment."
        case .offline:
            return "Couldn't reach Claude. Check your internet connection."
        case .refused:
            return "Claude declined to respond to this."
        case .truncated:
            return "The reply was cut off before it finished."
        case .rejected(let detail):
            return detail.isEmpty
                ? "Claude couldn't accept that request."
                : "Claude couldn't accept that request: \(detail)"
        case .server:
            return "Something went wrong on Claude's side. Try again in a moment."
        case .unexpected:
            return "Something unexpected went wrong. Try again."
        }
    }
}
