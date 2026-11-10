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
//  endpoint, headers, API version, streaming event format and error shapes.
//

import Foundation

final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"

    /// The provider the app uses. It is created the first time something asks for it.
    static let shared = AnthropicProvider(access: { AISettings.shared.access() })

    private let access: () -> AIAccess
    private let session: URLSession

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
                    let urlRequest = try self.authorizedRequest(for: request, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)

                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.unexpected
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 65_536 { break }
                        }
                        throw Self.error(forStatus: http.statusCode, body: body)
                    }

                    lines: for try await line in bytes.lines {
                        switch AnthropicStreamParser.parse(line: line) {
                        case .text(let piece):
                            continuation.yield(piece)
                        case .stopped(let reason):
                            if reason == "refusal" {
                                throw LLMError.refused
                            }
                        case .failed(let errorType):
                            throw Self.error(forErrorType: errorType)
                        case .finished:
                            break lines
                        case .ignored:
                            continue
                        }
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

    func complete(_ request: LLMRequest) async throws -> String {
        do {
            let urlRequest = try authorizedRequest(for: request, stream: false)
            let (data, response) = try await session.data(for: urlRequest)

            guard let http = response as? HTTPURLResponse else {
                throw LLMError.unexpected
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(forStatus: http.statusCode, body: data)
            }

            let message = try JSONDecoder().decode(MessageResponse.self, from: data)
            if message.stop_reason == "refusal" {
                throw LLMError.refused
            }
            if message.stop_reason == "max_tokens" {
                throw LLMError.truncated
            }
            return message.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined()
        } catch {
            throw Self.normalized(error)
        }
    }

    // MARK: - Building the request

    /// The gate. Throws before anything touches the network when AI is off or there is no key.
    private func authorizedRequest(for request: LLMRequest, stream: Bool) throws -> URLRequest {
        switch access() {
        case .off:
            throw LLMError.aiOff
        case .noKey:
            throw LLMError.missingKey
        case .allowed(let apiKey):
            return try Self.makeURLRequest(for: request, apiKey: apiKey, stream: stream)
        }
    }

    static func makeURLRequest(for request: LLMRequest, apiKey: String, stream: Bool) throws -> URLRequest {
        let body = RequestBody(
            model: request.model,
            max_tokens: request.maxTokens,
            system: (request.system?.isEmpty ?? true) ? nil : request.system,
            messages: request.messages.map { RequestBody.Message(role: $0.role.rawValue, content: $0.text) },
            stream: stream ? true : nil
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
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

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let max_tokens: Int
        let system: String?
        let messages: [Message]
        let stream: Bool?
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stop_reason: String?
    }

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
    /// Anything else: keep-alive pings, thinking, event names, and event types
    /// added in future. These are skipped on purpose.
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
