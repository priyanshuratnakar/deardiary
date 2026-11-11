//
//  SchemaOrderTests.swift
//  freewriteTests
//
//  Checks that a required reply shape reaches every AI service exactly as it is
//  written. A model writes its reply in the order the shape lists its fields,
//  so a shape whose fields have been sorted makes it name a thought's kind
//  before the thought. With a real local model that request never finished.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct SchemaOrderTests {

    private let shapes: [(name: String, data: Data)] = [("digest", DigestSchema.data), ("tidy", TidySchema.data)]

    private func text(of request: URLRequest) -> String {
        String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    }

    private func request(with shape: Data) -> LLMRequest {
        var request = Fixtures.request
        request.jsonSchema = shape
        return request
    }

    // MARK: - The slot

    @Test func theShapeIsSwappedInAsItsOwnText() throws {
        let slot = SchemaSlot()
        let body = try JSONSerialization.data(withJSONObject: ["format": slot.placeholder, "model": "m"], options: [.sortedKeys])
        let shape = Data(#"{"type":"object","properties":{"zebra":{},"apple":{}}}"#.utf8)

        let filled = String(data: slot.fill(body, with: shape), encoding: .utf8)

        // "zebra" stays before "apple": nothing was sorted.
        #expect(filled == #"{"format":{"type":"object","properties":{"zebra":{},"apple":{}}},"model":"m"}"#)
    }

    @Test func withNoShapeOrNoPlaceholderTheBodyIsLeftAlone() throws {
        let slot = SchemaSlot()
        let body = try JSONSerialization.data(withJSONObject: ["model": "m"], options: [.sortedKeys])

        #expect(slot.fill(body, with: nil) == body)
        #expect(slot.fill(body, with: DigestSchema.data) == body)
    }

    @Test func nothingAPersonWroteCanBeMistakenForThePlaceholder() throws {
        let first = SchemaSlot(), second = SchemaSlot()
        #expect(first.placeholder != second.placeholder)

        // Even a message that is exactly an old placeholder is not touched by a new request.
        let body = try JSONSerialization.data(withJSONObject: ["format": second.placeholder, "said": first.placeholder], options: [.sortedKeys])
        let filled = String(data: second.fill(body, with: Data("{}".utf8)), encoding: .utf8) ?? ""
        #expect(filled.contains("\"said\":\"\(first.placeholder)\""))
        #expect(filled.contains("\"format\":{}"))
    }

    // MARK: - Every service gets the shape as written

    @Test func ollamaGetsTheShapeAsWritten() throws {
        for shape in shapes {
            let urlRequest = try OllamaProvider.makeURLRequest(for: request(with: shape.data), base: URL(string: "http://ollama.test:11434")!, schema: true)
            let body = text(of: urlRequest)

            #expect(body.contains(String(data: shape.data, encoding: .utf8)!), "\(shape.name) was changed on the way")
            #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil)
            #expect(!body.contains("schema-slot-"))
        }
    }

    @Test func openAIAndOtherServicesGetTheShapeAsWritten() throws {
        let endpoints = [
            AIEndpoint(kind: .openai, baseURL: URL(string: "https://openai.test/v1")!, apiKey: Fixtures.fakeKey),
            AIEndpoint(kind: .other, baseURL: URL(string: "http://openai.test:1234/v1")!, apiKey: nil),
        ]
        for endpoint in endpoints {
            for shape in shapes {
                let urlRequest = try OpenAICompatibleProvider.makeURLRequest(for: request(with: shape.data), endpoint: endpoint, extras: true)
                let body = text(of: urlRequest)

                #expect(body.contains(String(data: shape.data, encoding: .utf8)!), "\(shape.name) was changed on the way")
                #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil)
                #expect(!body.contains("schema-slot-"))
            }
        }
    }

    @Test func claudeGetsTheShapeAsWritten() throws {
        for shape in shapes {
            let urlRequest = try AnthropicProvider.makeURLRequest(for: request(with: shape.data), apiKey: Fixtures.fakeKey, stream: true, extras: true)
            let body = text(of: urlRequest)

            #expect(body.contains(String(data: shape.data, encoding: .utf8)!), "\(shape.name) was changed on the way")
            #expect((try? JSONSerialization.jsonObject(with: Data(body.utf8))) != nil)
            #expect(!body.contains("schema-slot-"))
        }
    }

    @Test func whenTheShapeIsLeftOutNoPlaceholderIsLeftBehind() throws {
        let ollama = text(of: try OllamaProvider.makeURLRequest(for: request(with: DigestSchema.data), base: URL(string: "http://ollama.test:11434")!, schema: false))
        let claude = text(of: try AnthropicProvider.makeURLRequest(for: request(with: DigestSchema.data), apiKey: Fixtures.fakeKey, stream: true, extras: false))

        for body in [ollama, claude] {
            #expect(!body.contains("schema-slot-"))
            #expect(!body.contains("thought_updates"))
        }
    }

    // MARK: - The order that is written is the order that makes sense

    @Test func aThoughtIsNamedBeforeItIsDescribed() throws {
        let digest = try #require(String(data: DigestSchema.data, encoding: .utf8))
        func position(_ field: String, after start: String.Index? = nil) -> String.Index? {
            digest.range(of: "\"\(field)\": {", range: (start ?? digest.startIndex)..<digest.endIndex)?.lowerBound
        }

        // What the entry is about comes first; the profile, which rests on everything else, last.
        let summary = try #require(position("summary"))
        let newThoughts = try #require(position("new_thoughts"))
        let profile = try #require(position("profile"))
        #expect(summary < newThoughts)
        #expect(newThoughts < profile)

        // Inside a new thought: its name, then its kind.
        let label = try #require(position("label", after: newThoughts))
        let kind = try #require(position("kind", after: newThoughts))
        #expect(label < kind)
    }
}
