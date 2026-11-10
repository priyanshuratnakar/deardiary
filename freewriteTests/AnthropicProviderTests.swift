//
//  AnthropicProviderTests.swift
//  freewriteTests
//
//  Checks the Claude client without touching the real network:
//  - nothing is sent when AI is off or there is no key
//  - requests have the right address, headers and body
//  - replies, refusals and every kind of failure are handled plainly
//

import Foundation
import Testing
@testable import freewrite

// These tests share one stand-in network, so they run one at a time.
@Suite(.serialized) struct AnthropicProviderTests {

    private func provider(_ access: AIAccess) -> AnthropicProvider {
        AnthropicProvider(access: { access }, session: StubURLProtocol.makeSession())
    }

    // MARK: - The gate: AI off means zero network requests

    @Test func aiOffSendsNothingWhenStreaming() async {
        StubURLProtocol.install(.init(body: Fixtures.helloStream))

        let result = await collect(provider(.off).stream(Fixtures.request))

        #expect(result.error as? LLMError == .aiOff)
        #expect(result.text.isEmpty)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func aiOffSendsNothingWhenCompleting() async {
        StubURLProtocol.install(.init(body: Fixtures.messageBody(stopReason: "end_turn")))

        await #expect(throws: LLMError.aiOff) {
            _ = try await provider(.off).complete(Fixtures.request)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func missingKeySendsNothing() async {
        StubURLProtocol.install(.init(body: Fixtures.helloStream))

        let result = await collect(provider(.noKey).stream(Fixtures.request))

        #expect(result.error as? LLMError == .missingKey)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Request shape

    @Test func streamingRequestHasTheDocumentedShape() throws {
        let urlRequest = try AnthropicProvider.makeURLRequest(for: Fixtures.request, apiKey: Fixtures.fakeKey, stream: true)

        #expect(urlRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == Fixtures.fakeKey)
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(urlRequest.value(forHTTPHeaderField: "content-type") == "application/json")

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Only these fields are sent. In particular no temperature, top_p or top_k,
        // which the current API version rejects.
        #expect(Set(json.keys) == ["model", "max_tokens", "system", "messages", "stream"])
        #expect(json["model"] as? String == "test-model")
        #expect(json["max_tokens"] as? Int == 256)
        #expect(json["system"] as? String == "Test instructions.")
        #expect(json["stream"] as? Bool == true)

        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Hello there."]])
    }

    @Test func nonStreamingRequestLeavesOutStreamAndEmptySystem() throws {
        var request = Fixtures.request
        request.system = nil

        let urlRequest = try AnthropicProvider.makeURLRequest(for: request, apiKey: Fixtures.fakeKey, stream: false)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(Set(json.keys) == ["model", "max_tokens", "messages"])
    }

    @Test func theModelComesFromTheRequestNotTheClient() throws {
        var request = Fixtures.request
        request.model = "whatever-the-user-typed"

        let urlRequest = try AnthropicProvider.makeURLRequest(for: request, apiKey: Fixtures.fakeKey, stream: true)
        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "whatever-the-user-typed")
    }

    // MARK: - Streaming replies

    @Test func streamsTheReplyText() async {
        StubURLProtocol.install(.init(body: Fixtures.helloStream))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.error == nil)
        #expect(result.text == "Hello!")

        let sent = StubURLProtocol.requests
        #expect(sent.count == 1)
        #expect(sent.first?.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.first?.value(forHTTPHeaderField: "x-api-key") == Fixtures.fakeKey)
        #expect(sent.first?.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    }

    @Test func errorPartWayThroughAStreamIsReported() async {
        StubURLProtocol.install(.init(body: Fixtures.overloadedMidStream))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.text == "Hel")
        #expect(result.error as? LLMError == .overloaded)
    }

    @Test func refusalIsReported() async {
        StubURLProtocol.install(.init(body: Fixtures.refusedStream))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.error as? LLMError == .refused)
    }

    // MARK: - Failures

    @Test(arguments: [
        (401, "authentication_error", LLMError.invalidKey),
        (402, "billing_error", LLMError.billing),
        (403, "permission_error", LLMError.permission),
        (404, "not_found_error", LLMError.modelNotFound),
        (429, "rate_limit_error", LLMError.rateLimited),
        (500, "api_error", LLMError.server),
        (504, "timeout_error", LLMError.server),
        (529, "overloaded_error", LLMError.overloaded),
    ])
    func httpFailuresBecomePlainErrors(status: Int, type: String, expected: LLMError) async {
        StubURLProtocol.install(.init(status: status, body: Fixtures.errorBody(type: type, message: "Something happened.")))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.text.isEmpty)
        #expect(result.error as? LLMError == expected)
    }

    @Test func rejectedRequestKeepsTheServicesExplanation() async {
        StubURLProtocol.install(.init(status: 400, body: Fixtures.errorBody(type: "invalid_request_error", message: "max_tokens: must be positive")))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.error as? LLMError == .rejected(detail: "max_tokens: must be positive"))
    }

    @Test func noNetworkBecomesOffline() async {
        StubURLProtocol.install(.init(failure: .notConnectedToInternet))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.error as? LLMError == .offline)
    }

    @Test func garbageReplyDoesNotCrash() async {
        StubURLProtocol.install(.init(body: "<html>not what we expected</html>"))

        let result = await collect(provider(.allowed(apiKey: Fixtures.fakeKey)).stream(Fixtures.request))

        #expect(result.text.isEmpty)
        #expect(result.error == nil)
    }

    // MARK: - Whole replies (used later for building memory)

    @Test func completeJoinsTheTextBlocks() async throws {
        StubURLProtocol.install(.init(body: Fixtures.messageBody(stopReason: "end_turn")))

        let reply = try await provider(.allowed(apiKey: Fixtures.fakeKey)).complete(Fixtures.request)

        #expect(reply == "Hi there")
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func completeReportsRefusalAndCutOffReplies() async {
        StubURLProtocol.install(.init(body: Fixtures.messageBody(stopReason: "refusal")))
        await #expect(throws: LLMError.refused) {
            _ = try await provider(.allowed(apiKey: Fixtures.fakeKey)).complete(Fixtures.request)
        }

        StubURLProtocol.install(.init(body: Fixtures.messageBody(stopReason: "max_tokens")))
        await #expect(throws: LLMError.truncated) {
            _ = try await provider(.allowed(apiKey: Fixtures.fakeKey)).complete(Fixtures.request)
        }
    }

    @Test func completeReportsMalformedRepliesAsUnexpected() async {
        StubURLProtocol.install(.init(body: "{\"not\": \"a message\"}"))

        await #expect(throws: LLMError.unexpected) {
            _ = try await provider(.allowed(apiKey: Fixtures.fakeKey)).complete(Fixtures.request)
        }
    }

    // MARK: - Messages shown to the user

    @Test func userMessagesNeverMentionTheKey() {
        let all: [LLMError] = [
            .aiOff, .missingKey, .invalidKey, .billing, .permission, .modelNotFound, .rateLimited,
            .overloaded, .offline, .refused, .truncated, .rejected(detail: ""), .rejected(detail: "why"),
            .server, .unexpected,
        ]
        for error in all {
            #expect(!error.userMessage.isEmpty)
            #expect(!error.userMessage.contains(Fixtures.fakeKey))
        }
    }
}
