//
//  TestSupport.swift
//  freewriteTests
//
//  Helpers shared by the Dear Diary tests. Nothing here touches the real
//  network, the real journal folder or the real API key.
//

import Foundation
@testable import freewrite

/// Stands in for the network. Requests made through `StubURLProtocol.makeSession()`
/// never leave the Mac: they are counted and answered with a canned reply.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var body: String = ""
        /// When set, the request fails as if the network were down.
        var failure: URLError.Code? = nil
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs = [Stub()]
        private var seen: [URLRequest] = []

        func install(_ newStubs: [Stub]) {
            lock.lock()
            stubs = newStubs.isEmpty ? [Stub()] : newStubs
            seen = []
            lock.unlock()
        }

        /// Answers with the canned replies in order; the last one repeats.
        func record(_ request: URLRequest) -> Stub {
            lock.lock()
            defer { lock.unlock() }
            seen.append(request)
            return stubs.count > 1 ? stubs.removeFirst() : stubs[0]
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }
    }

    private static let state = State()

    /// Canned replies kept apart by host, for suites that run at the same time as others.
    private static let hostLock = NSLock()
    private static var hostStates: [String: State] = [:]

    private static func state(forHost host: String, create: Bool) -> State? {
        hostLock.lock()
        defer { hostLock.unlock() }
        if let existing = hostStates[host] { return existing }
        guard create else { return nil }
        let made = State()
        hostStates[host] = made
        return made
    }

    /// Sets the canned replies (used in order, the last one repeating) and forgets earlier requests.
    static func install(_ stubs: Stub...) {
        state.install(stubs)
    }

    /// The same, for requests to one made-up host only (for example "openai.test").
    static func install(forHost host: String, _ stubs: Stub...) {
        state(forHost: host, create: true)?.install(stubs)
    }

    /// Every request that tried to reach the network since the last `install`.
    static var requests: [URLRequest] {
        state.requests
    }

    /// Every request to one made-up host since its last `install`.
    static func requests(toHost host: String) -> [URLRequest] {
        state(forHost: host, create: false)?.requests ?? []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let hostState = request.url?.host.flatMap { Self.state(forHost: $0, create: false) }
        let stub = (hostState ?? Self.state).record(request)

        if let failure = stub.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }

        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Reads a streamed reply to the end and reports the text and any error.
func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (text: String, error: Error?) {
    var text = ""
    do {
        for try await piece in stream {
            text += piece
        }
        return (text, nil)
    } catch {
        return (text, error)
    }
}

enum Fixtures {
    /// A made-up key. It is never sent anywhere real.
    static let fakeKey = "test-key-not-real"

    static let request = LLMRequest(
        model: "test-model",
        system: "Test instructions.",
        messages: [LLMMessage(role: .user, text: "Hello there.")],
        maxTokens: 256
    )

    /// A complete streamed reply in the shape Anthropic's docs show: a thinking
    /// block with no visible text, a keep-alive ping, an event type that does not
    /// exist yet, and the text "Hello!" split in two.
    static let helloStream = """
    event: message_start
    data: {"type": "message_start", "message": {"id": "msg_test", "type": "message", "role": "assistant", "content": [], "model": "test-model", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}

    event: content_block_start
    data: {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}

    event: content_block_delta
    data: {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": ""}}

    event: content_block_delta
    data: {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "EqQBCgIYAhIM"}}

    event: content_block_stop
    data: {"type": "content_block_stop", "index": 0}

    event: content_block_start
    data: {"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}}

    event: ping
    data: {"type": "ping"}

    event: content_block_delta
    data: {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "Hello"}}

    event: some_future_event
    data: {"type": "some_future_event", "anything": {"nested": true}}

    event: content_block_delta
    data: {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "!"}}

    event: content_block_stop
    data: {"type": "content_block_stop", "index": 1}

    event: message_delta
    data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null}, "usage": {"output_tokens": 15}}

    event: message_stop
    data: {"type": "message_stop"}

    """

    /// A reply that starts, then the service reports it is overloaded.
    static let overloadedMidStream = """
    event: content_block_delta
    data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hel"}}

    event: error
    data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}

    """

    /// A reply the model's safety checks declined.
    static let refusedStream = """
    event: message_delta
    data: {"type": "message_delta", "delta": {"stop_reason": "refusal", "stop_sequence": null}, "usage": {"output_tokens": 0}}

    event: message_stop
    data: {"type": "message_stop"}

    """

    static func errorBody(type: String, message: String) -> String {
        """
        {"type": "error", "error": {"type": "\(type)", "message": "\(message)"}, "request_id": "req_test"}
        """
    }

    static func messageBody(stopReason: String) -> String {
        """
        {"id": "msg_test", "type": "message", "role": "assistant", "model": "test-model", "content": [{"type": "thinking", "thinking": "", "signature": "abc"}, {"type": "text", "text": "Hi "}, {"type": "text", "text": "there"}], "stop_reason": "\(stopReason)", "stop_sequence": null, "usage": {"input_tokens": 10, "output_tokens": 5}}
        """
    }
}
