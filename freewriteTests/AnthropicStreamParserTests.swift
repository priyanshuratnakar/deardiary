//
//  AnthropicStreamParserTests.swift
//  freewriteTests
//
//  Checks that each kind of line in a streamed reply is understood correctly.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct AnthropicStreamParserTests {

    @Test func textDeltaBecomesText() {
        let line = #"data: {"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "ello frien"}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .text("ello frien"))
    }

    @Test func textKeepsQuotesNewlinesAndEmoji() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"She said \"hi\"\nthen left 🙂"}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .text("She said \"hi\"\nthen left 🙂"))
    }

    @Test func thinkingAndSignatureAreSkipped() {
        let thinking = #"data: {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "private reasoning"}}"#
        let signature = #"data: {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "EqQBCgIYAhIM"}}"#
        let toolInput = #"data: {"type": "content_block_delta","index": 1,"delta": {"type": "input_json_delta","partial_json": "{\"location\": \"San Fra"}}"#
        #expect(AnthropicStreamParser.parse(line: thinking) == .ignored)
        #expect(AnthropicStreamParser.parse(line: signature) == .ignored)
        #expect(AnthropicStreamParser.parse(line: toolInput) == .ignored)
    }

    @Test func stopReasonIsReported() {
        let line = #"data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null}, "usage": {"output_tokens": 15}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .stopped(reason: "end_turn"))
    }

    @Test func refusalIsReportedAsAStopReason() {
        let line = #"data: {"type": "message_delta", "delta": {"stop_reason": "refusal", "stop_sequence": null}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .stopped(reason: "refusal"))
    }

    @Test func messageStopFinishes() {
        #expect(AnthropicStreamParser.parse(line: #"data: {"type": "message_stop"}"#) == .finished)
    }

    @Test func errorEventIsReported() {
        let line = #"data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .failed(errorType: "overloaded_error"))
    }

    @Test func pingsEventNamesAndBlankLinesAreSkipped() {
        #expect(AnthropicStreamParser.parse(line: #"data: {"type": "ping"}"#) == .ignored)
        #expect(AnthropicStreamParser.parse(line: "event: content_block_delta") == .ignored)
        #expect(AnthropicStreamParser.parse(line: "") == .ignored)
        #expect(AnthropicStreamParser.parse(line: ": keep-alive comment") == .ignored)
    }

    @Test func unknownFutureEventsAreSkipped() {
        let line = #"data: {"type": "some_future_event", "anything": {"nested": true}}"#
        #expect(AnthropicStreamParser.parse(line: line) == .ignored)
    }

    @Test func brokenJSONIsSkippedQuietly() {
        #expect(AnthropicStreamParser.parse(line: "data: {not json") == .ignored)
        #expect(AnthropicStreamParser.parse(line: "data:") == .ignored)
    }

    @Test func wholeExampleStreamProducesHello() {
        let events = Fixtures.helloStream
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { AnthropicStreamParser.parse(line: String($0)) }
            .filter { $0 != .ignored }

        #expect(events == [
            .text("Hello"),
            .text("!"),
            .stopped(reason: "end_turn"),
            .finished,
        ])
    }
}
