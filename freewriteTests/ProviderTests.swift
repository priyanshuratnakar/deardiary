//
//  ProviderTests.swift
//  freewriteTests
//
//  Checks the choice of AI service and the two clients added beside Claude's:
//  the OpenAI chat format and Ollama on this Mac. Nothing here touches the
//  real network, a real key or the real preferences.
//

import Combine
import Foundation
import Testing
@testable import freewrite

// MARK: - Settings: which service, and is it ready?

@Suite struct AIProviderSettingsTests {

    @Test func claudeIsTheServiceUntilAnotherIsChosenAndEarlierChoicesCarryOver() {
        let box = SettingsBox()
        box.defaults.set("a-claude-model-picked-before", forKey: "ai.talkModel")

        let settings = box.settings()

        #expect(settings.provider == .claude)
        #expect(settings.savedProvider() == .claude)
        #expect(settings.talkModel == "a-claude-model-picked-before")
        #expect(settings.digestModel == AISettings.defaultDigestModel)
    }

    @Test func theServicesAreOfferedInOneOrderWithPlainNames() {
        #expect(AIProviderKind.allCases.map(\.title) == ["On this Mac", "OpenAI", "Claude", "Other"])
        #expect(AIProviderKind.allCases.map(\.needsKey) == [false, true, true, false])
    }

    @Test func eachServiceRemembersItsOwnModelsAndItsOwnKey() {
        let box = SettingsBox()
        let settings = box.settings()
        settings.saveAPIKey("made-up-claude-key")
        settings.talkModel = "claude-talk-test"

        settings.provider = .openai
        #expect(settings.hasAPIKey == false)
        #expect(settings.talkModel == "")
        #expect(settings.digestModel == "")
        settings.saveAPIKey("made-up-openai-key")
        settings.talkModel = "openai-talk-test"
        settings.digestModel = "openai-memory-test"

        settings.provider = .local
        #expect(settings.hasAPIKey == false)
        settings.talkModel = "local-test"

        settings.provider = .claude
        #expect(settings.hasAPIKey)
        #expect(settings.talkModel == "claude-talk-test")

        settings.provider = .openai
        #expect(settings.talkModel == "openai-talk-test")
        #expect(settings.digestModel == "openai-memory-test")

        // The app, started again, finds everything as it was left.
        let again = box.settings()
        #expect(again.provider == .openai)
        #expect(again.hasAPIKey)
        #expect(again.talkModel == "openai-talk-test")

        // Removing one service's key leaves the other's alone.
        settings.removeAPIKey()
        #expect(settings.hasAPIKey == false)
        settings.provider = .claude
        #expect(settings.hasAPIKey)
    }

    @Test func whatIsStillMissingIsNamedForEachService() {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true

        // Claude has a default model, so only the key is missing.
        #expect(settings.setupGap == .key)
        #expect(settings.isReady == false)
        settings.saveAPIKey("made-up-claude-key")
        #expect(settings.setupGap == nil)
        #expect(settings.isReady)

        // OpenAI has no default model: one must be picked.
        settings.provider = .openai
        #expect(settings.setupGap == .key)
        settings.saveAPIKey("made-up-openai-key")
        #expect(settings.setupGap == .model)
        settings.talkModel = "openai-talk-test"
        #expect(settings.isReady)

        // "Other" needs an address and a model. A key is optional.
        settings.provider = .other
        #expect(settings.setupGap == .address)
        settings.otherBaseURL = "http://localhost:1234/v1"
        #expect(settings.setupGap == .model)
        settings.talkModel = "other-test"
        #expect(settings.isReady)

        // On this Mac needs only a model.
        settings.provider = .local
        #expect(settings.setupGap == .model)
        settings.talkModel = "local-test"
        #expect(settings.isReady)

        settings.aiEnabled = false
        #expect(settings.isReady == false)
    }

    @Test func eachGateOnlyOpensForTheChosenServiceAndOnlyWithAIOn() {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.saveAPIKey("made-up-claude-key")

        #expect(settings.access() == .allowed(apiKey: "made-up-claude-key"))
        #expect(settings.endpointAccess() == .off)
        #expect(settings.localAccess() == false)

        settings.provider = .openai
        #expect(settings.access() == .off)
        #expect(settings.endpointAccess() == .noKey)
        settings.saveAPIKey("made-up-openai-key")
        #expect(settings.endpointAccess() == .allowed(AIEndpoint(kind: .openai, baseURL: AISettings.openAIBaseURL, apiKey: "made-up-openai-key")))
        #expect(settings.localAccess() == false)

        settings.provider = .other
        #expect(settings.endpointAccess() == .noAddress)
        settings.otherBaseURL = "  http://localhost:1234/v1 "
        #expect(settings.endpointAccess() == .allowed(AIEndpoint(kind: .other, baseURL: URL(string: "http://localhost:1234/v1")!, apiKey: nil)))

        settings.provider = .local
        #expect(settings.localAccess())
        #expect(settings.access() == .off)
        #expect(settings.endpointAccess() == .off)

        // With AI off, every gate is shut whatever is chosen.
        settings.aiEnabled = false
        for kind in AIProviderKind.allCases {
            settings.provider = kind
            #expect(settings.access() == .off)
            #expect(settings.endpointAccess() == .off)
            #expect(settings.localAccess() == false)
        }
    }

    @Test func memoryNeedsTheChosenServiceToBeSetUpWithAMemoryModel() {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.memoryEnabled = true

        #expect(settings.memoryAllowed() == false)
        settings.saveAPIKey("made-up-claude-key")
        #expect(settings.memoryAllowed())
        #expect(settings.savedDigestModel() == AISettings.defaultDigestModel)

        settings.provider = .local
        #expect(settings.memoryAllowed() == false)
        settings.digestModel = "local-memory-test"
        #expect(settings.memoryAllowed())
        #expect(settings.savedDigestModel() == "local-memory-test")

        settings.provider = .other
        settings.digestModel = "other-memory-test"
        #expect(settings.memoryAllowed() == false)
        settings.otherBaseURL = "https://example.test/v1"
        #expect(settings.memoryAllowed())

        settings.memoryEnabled = false
        #expect(settings.memoryAllowed() == false)
    }

    @Test(arguments: [
        ("http://localhost:1234/v1", true),
        ("https://example.test/v1", true),
        ("  https://example.test/v1  ", true),
        ("localhost:1234", false),
        ("ftp://example.test", false),
        ("just some words", false),
        ("", false),
    ])
    func anAddressMustBeAWebAddress(text: String, accepted: Bool) {
        #expect((AISettings.address(from: text) != nil) == accepted)
    }

    @Test func readinessIsAnnouncedTheMomentItChanges() {
        let box = SettingsBox()
        let settings = box.settings()
        var seen: [Bool] = []
        let watching = settings.readiness.sink { seen.append($0) }
        defer { watching.cancel() }

        settings.aiEnabled = true
        settings.saveAPIKey("made-up-claude-key")
        settings.provider = .local
        settings.talkModel = "local-test"
        settings.aiEnabled = false

        // Off, ready with Claude, not ready on this Mac until a model is chosen, ready, then off.
        #expect(seen == [false, true, false, true, false])
    }
}

// MARK: - Messages name the service in use

@Suite struct ServiceMessageTests {

    @Test func theSameProblemIsDescribedInTheNameOfTheServiceInUse() {
        #expect(LLMError.offline.userMessage(for: .claude) == "Couldn't reach Claude. Check your internet connection.")
        #expect(LLMError.offline.userMessage(for: .openai) == "Couldn't reach OpenAI. Check your internet connection.")
        #expect(LLMError.offline.userMessage(for: .local) == "Couldn't reach Ollama. Open the Ollama app, then try again.")
        #expect(LLMError.offline.userMessage(for: .other) == "Couldn't reach the AI service. Check the address in Settings and your connection.")

        #expect(LLMError.invalidKey.userMessage(for: .openai) == "OpenAI didn't accept that API key. Check it and save it again.")
        #expect(LLMError.billing.userMessage(for: .openai) == "There's a billing problem on your OpenAI account. Check your credits there.")
        #expect(LLMError.overloaded.userMessage(for: .other) == "The AI service is busy right now. Try again in a moment.")
        #expect(LLMError.server.userMessage(for: .other) == "Something went wrong on the AI service's side. Try again in a moment.")
        #expect(LLMError.server.userMessage(for: .local) == "Something went wrong in Ollama. Try again in a moment.")
        #expect(LLMError.modelNotFound.userMessage(for: .local) == "That model isn't on this Mac any more. Pick another in Settings.")
        #expect(LLMError.missingModel.userMessage(for: .local) == "No model chosen yet. Pick one in Settings.")
        #expect(LLMError.missingAddress.userMessage(for: .other) == "No address yet. Add one in Settings.")
        #expect(Prompts.talkDeclined(by: .local).hasPrefix("Ollama declined to respond to this."))
    }

    @Test func withClaudeEveryMessageReadsAsItDidBefore() {
        let all: [LLMError] = [.aiOff, .missingKey, .invalidKey, .billing, .permission, .modelNotFound, .rateLimited, .overloaded, .offline, .refused, .truncated, .rejected(detail: ""), .rejected(detail: "too long"), .server, .unexpected]
        for error in all {
            #expect(error.userMessage == error.userMessage(for: .claude))
        }
        #expect(LLMError.billing.userMessage == "There's a billing problem on your Anthropic account. Check your credits there.")
        #expect(LLMError.server.userMessage == "Something went wrong on Claude's side. Try again in a moment.")
        #expect(Prompts.talkDeclinedNotice == Prompts.talkDeclined(by: .claude))
    }

    @Test func noMessageIsEmptyOrCarriesRawDetailsForAnyService() {
        let all: [LLMError] = [.aiOff, .missingKey, .missingAddress, .missingModel, .invalidKey, .billing, .permission, .modelNotFound, .rateLimited, .overloaded, .offline, .refused, .truncated, .rejected(detail: ""), .server, .unexpected]
        for kind in AIProviderKind.allCases {
            for error in all {
                let message = error.userMessage(for: kind)
                #expect(message.count > 15)
                #expect(message.hasSuffix("."))
                #expect(!message.contains("Error"))
            }
        }
    }
}

// MARK: - Thinking mixed into a reply

@Suite struct ThinkTagFilterTests {

    private func run(_ pieces: [String]) -> String {
        var filter = ThinkTagFilter()
        var shown = pieces.map { filter.feed($0) }.joined()
        shown += filter.finish()
        return shown
    }

    @Test func ordinaryTextPassesStraightThrough() {
        #expect(run(["Hel", "lo ", "there."]) == "Hello there.")
        #expect(run(["2 < 3 and 5 > 4."]) == "2 < 3 and 5 > 4.")
    }

    @Test func aThinkingBlockIsRemovedAlongWithTheGapItLeaves() {
        #expect(run(["<think>They seem tired.</think>\n\nYou sound tired."]) == "You sound tired.")
    }

    @Test func tagsSplitAcrossPiecesAreStillCaught() {
        #expect(run(["<th", "ink>private", " thoughts</thi", "nk>\n", "What I say."]) == "What I say.")
    }

    @Test func textThatOnlyLooksLikeTheStartOfATagIsNotLost() {
        #expect(run(["A <thing> happened", " today <t"]) == "A <thing> happened today <t")
    }

    @Test func aThinkingBlockThatNeverEndsShowsNothing() {
        #expect(run(["<think>still going"]) == "")
    }
}

// MARK: - The OpenAI chat format

// These tests share a stand-in network (kept apart from the Claude tests by host), so they run one at a time.
@Suite(.serialized) struct OpenAICompatibleProviderTests {

    private let host = "openai.test"
    private var openAI: AIEndpoint { AIEndpoint(kind: .openai, baseURL: URL(string: "https://openai.test/v1")!, apiKey: Fixtures.fakeKey) }
    private var other: AIEndpoint { AIEndpoint(kind: .other, baseURL: URL(string: "http://openai.test:1234/v1")!, apiKey: nil) }

    private func provider(_ access: AIEndpointAccess) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(access: { access }, session: StubURLProtocol.makeSession())
    }

    // The gate

    @Test(arguments: [
        (AIEndpointAccess.off, LLMError.aiOff),
        (AIEndpointAccess.noKey, LLMError.missingKey),
        (AIEndpointAccess.noAddress, LLMError.missingAddress),
    ])
    func nothingIsSentUnlessTheServiceIsSetUp(access: AIEndpointAccess, expected: LLMError) async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIHello))

        let streamed = await collect(provider(access).stream(Fixtures.request))
        #expect(streamed.error as? LLMError == expected)
        await #expect(throws: expected) { _ = try await provider(access).complete(Fixtures.request) }
        await #expect(throws: expected) { _ = try await provider(access).models() }

        #expect(StubURLProtocol.requests(toHost: host).isEmpty)
    }

    // Request shape

    @Test func aRequestToOpenAIHasTheDocumentedShape() throws {
        let urlRequest = try OpenAICompatibleProvider.makeURLRequest(for: Fixtures.request, endpoint: openAI, extras: true)

        #expect(urlRequest.url?.absoluteString == "https://openai.test/v1/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.fakeKey)")
        #expect(urlRequest.value(forHTTPHeaderField: "content-type") == "application/json")

        let body = ProviderFixtures.body(of: urlRequest)
        #expect(body["model"] as? String == "test-model")
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_completion_tokens"] as? Int == 256)
        #expect(body["max_tokens"] == nil)
        #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect(body["response_format"] == nil)
        // Nothing the service might reject, and nothing that changes how the model writes.
        #expect(body["temperature"] == nil)

        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": "Test instructions."],
            ["role": "user", "content": "Hello there."],
        ])
    }

    @Test func aRequestToAnotherServiceUsesTheOlderNamesAndNoKeyWhenThereIsNone() throws {
        let urlRequest = try OpenAICompatibleProvider.makeURLRequest(for: Fixtures.request, endpoint: other, extras: true)

        #expect(urlRequest.url?.absoluteString == "http://openai.test:1234/v1/chat/completions")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)
        let body = ProviderFixtures.body(of: urlRequest)
        #expect(body["max_tokens"] as? Int == 256)
        #expect(body["max_completion_tokens"] == nil)
        #expect(body["stream_options"] == nil)
    }

    @Test func aRequiredShapeIsSentAsAStrictSchemaAndLeftOutOfAPlainRequest() throws {
        var request = Fixtures.request
        request.jsonSchema = DigestSchema.data

        let full = ProviderFixtures.body(of: try OpenAICompatibleProvider.makeURLRequest(for: request, endpoint: openAI, extras: true))
        let format = try #require(full["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect(schema["name"] as? String == "reply")
        #expect((schema["schema"] as? [String: Any])?["type"] as? String == "object")

        let plain = ProviderFixtures.body(of: try OpenAICompatibleProvider.makeURLRequest(for: request, endpoint: openAI, extras: false))
        #expect(plain["response_format"] == nil)
        #expect(plain["max_completion_tokens"] == nil)
        #expect(plain["model"] as? String == "test-model")
    }

    // Replies

    @Test func aStreamedReplyArrivesPieceByPiece() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIHello))

        let result = await collect(provider(.allowed(openAI)).stream(Fixtures.request))

        #expect(result.error == nil)
        #expect(result.text == "Hello!")
        let sent = StubURLProtocol.requests(toHost: host)
        #expect(sent.count == 1)
        #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.fakeKey)")
    }

    @Test func aWholeReplyComesWithItsTokenCounts() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIHello))

        let reply = try await provider(.allowed(openAI)).complete(Fixtures.request)

        #expect(reply == LLMReply(text: "Hello!", inputTokens: 25, outputTokens: 7))
    }

    @Test func thinkingMixedIntoTheReplyIsNeverShown() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIStream(pieces: ["<think>They said ", "hello.</think>\n\n", "Hello ", "back."])))

        let reply = try await provider(.allowed(other)).complete(Fixtures.request)

        #expect(reply.text == "Hello back.")
    }

    @Test func aServiceThatLeavesOutTheClosingLineIsStillUnderstood() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIStream(pieces: ["Fine."], done: false)))

        #expect(try await provider(.allowed(other)).complete(Fixtures.request).text == "Fine.")
    }

    @Test func aDeclinedReplyIsReportedAsDeclined() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIRefusal))
        let refused = await collect(provider(.allowed(openAI)).stream(Fixtures.request))
        #expect(refused.error as? LLMError == .refused)
        #expect(refused.text.isEmpty)

        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIStream(pieces: ["I"], finishReason: "content_filter")))
        await #expect(throws: LLMError.refused) { _ = try await provider(.allowed(openAI)).complete(Fixtures.request) }
    }

    @Test func aReplyThatRanOutOfRoomIsReportedAsCutOff() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIStream(pieces: ["{\"summary\": \"half"], finishReason: "length")))

        await #expect(throws: LLMError.truncated) { _ = try await provider(.allowed(openAI)).complete(Fixtures.request) }
    }

    @Test func aReplyThatStopsWithoutSayingWhyIsNotTrusted() async {
        StubURLProtocol.install(forHost: host, .init(body: "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hel\"},\"finish_reason\":null}]}\n\n"))

        await #expect(throws: LLMError.unexpected) { _ = try await provider(.allowed(openAI)).complete(Fixtures.request) }
    }

    @Test func aProblemPartWayThroughIsReportedPlainly() async {
        StubURLProtocol.install(forHost: host, .init(body: "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hel\"},\"finish_reason\":null}]}\n\ndata: " + ProviderFixtures.openAIError(message: "Overloaded", type: "service_unavailable_error") + "\n\n"))

        let result = await collect(provider(.allowed(openAI)).stream(Fixtures.request))

        #expect(result.error as? LLMError == .overloaded)
    }

    // Failures

    @Test(arguments: [
        (401, ProviderFixtures.openAIError(message: "Incorrect API key provided", type: "invalid_request_error", code: "invalid_api_key"), LLMError.invalidKey),
        (403, ProviderFixtures.openAIError(message: "Not allowed"), LLMError.permission),
        (404, ProviderFixtures.openAIError(message: "The model does not exist", code: "model_not_found"), LLMError.modelNotFound),
        (429, ProviderFixtures.openAIError(message: "Rate limit reached for requests", type: "rate_limit_error"), LLMError.rateLimited),
        (429, ProviderFixtures.openAIError(message: "You exceeded your current quota", type: "insufficient_quota", code: "credit_balance_exhausted"), LLMError.billing),
        (429, ProviderFixtures.openAIError(message: "Spend limit", type: "invalid_request_error", code: "project_spend_limit_exceeded"), LLMError.billing),
        (503, ProviderFixtures.openAIError(message: "Overloaded", type: "service_unavailable_error", code: "server_is_overloaded"), LLMError.overloaded),
        (500, "<html>broken</html>", LLMError.server),
        (422, "{\"error\":\"that is not valid\"}", LLMError.rejected(detail: "that is not valid")),
    ])
    func everyKindOfFailureBecomesAPlainError(status: Int, body: String, expected: LLMError) async {
        StubURLProtocol.install(forHost: host, .init(status: status, body: body))

        let result = await collect(provider(.allowed(openAI)).stream(Fixtures.request))

        #expect(result.error as? LLMError == expected)
        #expect(result.text.isEmpty)
    }

    @Test func noConnectionIsReportedAsOffline() async {
        StubURLProtocol.install(forHost: host, .init(failure: .cannotConnectToHost))

        await #expect(throws: LLMError.offline) { _ = try await provider(.allowed(other)).complete(Fixtures.request) }
    }

    @Test func aModelThatRejectsTheOptionalPartsIsAskedAgainPlainlyAndRemembered() async throws {
        var request = Fixtures.request
        request.jsonSchema = DigestSchema.data
        let provider = provider(.allowed(openAI))
        StubURLProtocol.install(
            forHost: host,
            .init(status: 400, body: ProviderFixtures.openAIError(message: "Unsupported parameter: response_format")),
            .init(body: ProviderFixtures.openAIHello)
        )

        #expect(try await provider.complete(request).text == "Hello!")
        #expect(StubURLProtocol.requests(toHost: host).count == 2)

        // The next request for that model goes straight to the plain form.
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIHello))
        #expect(try await provider.complete(request).text == "Hello!")
        #expect(StubURLProtocol.requests(toHost: host).count == 1)
    }

    @Test func aRequestThatIsRejectedEvenInItsPlainFormSaysWhy() async {
        StubURLProtocol.install(forHost: host, .init(status: 400, body: ProviderFixtures.openAIError(message: "This model's maximum context length is 8192 tokens.")))

        await #expect(throws: LLMError.rejected(detail: "This model's maximum context length is 8192 tokens.")) {
            _ = try await provider(.allowed(openAI)).complete(Fixtures.request)
        }
        #expect(StubURLProtocol.requests(toHost: host).count == 2)
    }

    // The model list

    @Test func openAIsListLeavesOutModelsThatCannotHoldAConversationNewestFirst() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIModels))

        let models = try await provider(.allowed(openAI)).models()

        #expect(models.map(\.id) == ["newer-chat-model", "older-chat-model"])
        let sent = try #require(StubURLProtocol.requests(toHost: host).first)
        #expect(sent.url?.absoluteString == "https://openai.test/v1/models")
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.fakeKey)")
    }

    @Test func anotherServicesListIsShownWholeInNameOrder() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.openAIModels))

        let models = try await provider(.allowed(other)).models()

        #expect(models.map(\.id) == ["newer-chat-model", "older-chat-model", "text-embedding-test", "tts-test", "whisper-test"])
    }

    @Test func aServiceWithNoModelListSaysSoPlainly() async {
        StubURLProtocol.install(forHost: host, .init(status: 404, body: "Not Found"))
        await #expect(throws: LLMError.modelNotFound) { _ = try await provider(.allowed(other)).models() }

        StubURLProtocol.install(forHost: host, .init(body: "<html>hello</html>"))
        #expect((try? await provider(.allowed(other)).models()) == [])
    }
}

// MARK: - Ollama, on this Mac

@Suite(.serialized) struct OllamaProviderTests {

    private let host = "ollama.test"
    private let base = URL(string: "http://ollama.test:11434")!

    private func provider(allowed: Bool = true) -> OllamaProvider {
        OllamaProvider(isAllowed: { allowed }, base: base, session: StubURLProtocol.makeSession())
    }

    @Test func nothingIsSentWhileAIIsOffOrAnotherServiceIsChosen() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaHello))

        let streamed = await collect(provider(allowed: false).stream(Fixtures.request))
        #expect(streamed.error as? LLMError == .aiOff)
        await #expect(throws: LLMError.aiOff) { _ = try await provider(allowed: false).complete(Fixtures.request) }
        await #expect(throws: LLMError.aiOff) { _ = try await provider(allowed: false).models() }

        #expect(StubURLProtocol.requests(toHost: host).isEmpty)
    }

    @Test func theAppOnlyEverLooksForOllamaOnThisMac() {
        #expect(AISettings.localBaseURL.absoluteString == "http://localhost:11434")
    }

    @Test func aRequestHasTheDocumentedShapeAndAsksForEnoughRoom() throws {
        let urlRequest = try OllamaProvider.makeURLRequest(for: Fixtures.request, base: base, schema: true)

        #expect(urlRequest.url?.absoluteString == "http://ollama.test:11434/api/chat")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let body = ProviderFixtures.body(of: urlRequest)
        #expect(body["model"] as? String == "test-model")
        #expect(body["stream"] as? Bool == true)
        #expect(body["format"] == nil)
        let options = try #require(body["options"] as? [String: Any])
        // Ollama's own default is about 4,000 tokens, which would cut an entry and its memory short.
        #expect(options["num_ctx"] as? Int == AILimits.localContextTokens)
        #expect(AILimits.localContextTokens >= 16_000)
        #expect(options["num_predict"] as? Int == 256)

        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": "Test instructions."],
            ["role": "user", "content": "Hello there."],
        ])
    }

    @Test func aRequiredShapeIsPassedAsTheSchemaItself() throws {
        var request = Fixtures.request
        request.jsonSchema = DigestSchema.data

        let with = ProviderFixtures.body(of: try OllamaProvider.makeURLRequest(for: request, base: base, schema: true))
        #expect((with["format"] as? [String: Any])?["type"] as? String == "object")

        let without = ProviderFixtures.body(of: try OllamaProvider.makeURLRequest(for: request, base: base, schema: false))
        #expect(without["format"] == nil)
    }

    @Test func aStreamedReplyArrivesPieceByPieceWithoutThePrivateThinking() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaHello))

        let result = await collect(provider().stream(Fixtures.request))

        #expect(result.error == nil)
        #expect(result.text == "Hello!")
        #expect(StubURLProtocol.requests(toHost: host).count == 1)
    }

    @Test func aWholeReplyComesWithItsTokenCounts() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaHello))

        #expect(try await provider().complete(Fixtures.request) == LLMReply(text: "Hello!", inputTokens: 25, outputTokens: 7))
    }

    @Test func thinkingMixedIntoTheReplyIsNeverShown() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaStream(pieces: ["<think>hmm</th", "ink>\n", "Hello back."])))

        #expect(try await provider().complete(Fixtures.request).text == "Hello back.")
    }

    @Test func aReplyThatRanOutOfRoomIsReportedAsCutOff() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaStream(pieces: ["{\"summary\": \"half"], doneReason: "length")))

        await #expect(throws: LLMError.truncated) { _ = try await provider().complete(Fixtures.request) }
    }

    @Test func aReplyWithoutItsClosingLineIsNotTrusted() async {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaStream(pieces: ["Hel"], doneReason: nil)))

        await #expect(throws: LLMError.unexpected) { _ = try await provider().complete(Fixtures.request) }
    }

    @Test func aProblemPartWayThroughIsReportedPlainly() async {
        StubURLProtocol.install(forHost: host, .init(body: "{\"message\":{\"role\":\"assistant\",\"content\":\"Hel\"},\"done\":false}\n{\"error\":\"an error was encountered while running the model\"}\n"))

        let result = await collect(provider().stream(Fixtures.request))

        #expect(result.error as? LLMError == .server)
    }

    @Test(arguments: [
        (404, "{\"error\":\"model 'test-model' not found\"}", LLMError.modelNotFound),
        (500, "{\"error\":\"the model failed to generate a response\"}", LLMError.server),
        (429, "{\"error\":\"too many requests\"}", LLMError.rateLimited),
    ])
    func everyKindOfFailureBecomesAPlainError(status: Int, body: String, expected: LLMError) async {
        StubURLProtocol.install(forHost: host, .init(status: status, body: body))

        let result = await collect(provider().stream(Fixtures.request))

        #expect(result.error as? LLMError == expected)
    }

    @Test func whenOllamaIsNotRunningItIsReportedAsOffline() async {
        StubURLProtocol.install(forHost: host, .init(failure: .cannotConnectToHost))

        await #expect(throws: LLMError.offline) { _ = try await provider().complete(Fixtures.request) }
        await #expect(throws: LLMError.offline) { _ = try await provider().models() }
    }

    @Test func aModelThatCannotFollowARequiredShapeIsAskedAgainWithoutItAndRemembered() async throws {
        var request = Fixtures.request
        request.jsonSchema = DigestSchema.data
        let provider = provider()
        StubURLProtocol.install(
            forHost: host,
            .init(status: 400, body: "{\"error\":\"this model does not support format\"}"),
            .init(body: ProviderFixtures.ollamaHello)
        )

        #expect(try await provider.complete(request).text == "Hello!")
        #expect(StubURLProtocol.requests(toHost: host).count == 2)

        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaHello))
        #expect(try await provider.complete(request).text == "Hello!")
        #expect(StubURLProtocol.requests(toHost: host).count == 1)
    }

    @Test func theModelsInstalledOnThisMacAreListedByNameWithTheirSize() async throws {
        StubURLProtocol.install(forHost: host, .init(body: ProviderFixtures.ollamaTags))

        let models = try await provider().models()

        #expect(models == [
            AIModelChoice(id: "gemma-test", name: "gemma-test", detail: "4.3B"),
            AIModelChoice(id: "qwen-test:8b", name: "qwen-test:8b", detail: "8.2B"),
        ])
        #expect(StubURLProtocol.requests(toHost: host).first?.url?.absoluteString == "http://ollama.test:11434/api/tags")
    }
}

// MARK: - Claude's model list

extension AnthropicProviderTests {

    @Test func claudesModelsAreListedByTheNamesAnthropicGivesThemNewestFirst() async throws {
        StubURLProtocol.install(.init(body: ProviderFixtures.claudeModels))
        let provider = AnthropicProvider(access: { .allowed(apiKey: Fixtures.fakeKey) }, session: StubURLProtocol.makeSession())

        let models = try await provider.models()

        // The one on its way out is left off.
        #expect(models == [
            AIModelChoice(id: "claude-newest-test", name: "Claude Newest"),
            AIModelChoice(id: "claude-small-test", name: "Claude Small"),
        ])
        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100")
        #expect(sent.value(forHTTPHeaderField: "x-api-key") == Fixtures.fakeKey)
        #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    }

    @Test func theModelListIsNotAskedForWhileAIIsOffOrThereIsNoKey() async {
        StubURLProtocol.install(.init(body: ProviderFixtures.claudeModels))

        await #expect(throws: LLMError.aiOff) {
            _ = try await AnthropicProvider(access: { .off }, session: StubURLProtocol.makeSession()).models()
        }
        await #expect(throws: LLMError.missingKey) {
            _ = try await AnthropicProvider(access: { .noKey }, session: StubURLProtocol.makeSession()).models()
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func aWrongKeyIsReportedWhenAskingForModels() async {
        StubURLProtocol.install(.init(status: 401, body: Fixtures.errorBody(type: "authentication_error", message: "invalid x-api-key")))

        await #expect(throws: LLMError.invalidKey) {
            _ = try await AnthropicProvider(access: { .allowed(apiKey: Fixtures.fakeKey) }, session: StubURLProtocol.makeSession()).models()
        }
    }
}

// MARK: - Sending each request to the chosen service

@Suite struct AIRouterTests {

    private func router(_ kind: @escaping () -> AIProviderKind, claude: FakeProvider, openAI: FakeProvider, local: FakeProvider) -> AIRouter {
        AIRouter(kind: kind, claude: { claude }, openAIStyle: { openAI }, local: { local })
    }

    @Test func eachRequestGoesToTheServiceChosenAtThatMoment() async throws {
        let claude = FakeProvider([.reply(["from Claude"])])
        let openAI = FakeProvider([.reply(["from OpenAI"]), .reply(["from the other service"])])
        let local = FakeProvider([.reply(["from this Mac"])])
        var chosen = AIProviderKind.claude
        let router = router({ chosen }, claude: claude, openAI: openAI, local: local)

        #expect(try await router.complete(Fixtures.request).text == "from Claude")
        chosen = .openai
        #expect(try await router.complete(Fixtures.request).text == "from OpenAI")
        chosen = .other
        #expect(try await router.complete(Fixtures.request).text == "from the other service")
        chosen = .local
        #expect(await collect(router.stream(Fixtures.request)).text == "from this Mac")

        #expect(claude.requests.count == 1)
        #expect(openAI.requests.count == 2)
        #expect(local.requests.count == 1)
    }

    @Test func aRequestWithNoModelIsNeverSent() async {
        let claude = FakeProvider(), openAI = FakeProvider(), local = FakeProvider()
        let router = router({ .local }, claude: claude, openAI: openAI, local: local)
        var request = Fixtures.request
        request.model = ""

        await #expect(throws: LLMError.missingModel) { _ = try await router.complete(request) }
        #expect(await collect(router.stream(request)).error as? LLMError == .missingModel)
        #expect(claude.requests.isEmpty && openAI.requests.isEmpty && local.requests.isEmpty)
    }
}

// MARK: - The model list in Settings

@MainActor
@Suite struct ModelCatalogTests {

    private let found = [AIModelChoice(id: "gemma-test", name: "gemma-test"), AIModelChoice(id: "qwen-test:8b", name: "qwen-test:8b")]

    @Test func nothingIsAskedWhileAIIsOffOrAKeyOrAddressIsMissing() async {
        let box = SettingsBox()
        let settings = box.settings()
        var asked = 0
        let catalog = ModelCatalog(fetch: { asked += 1; return [] })

        await catalog.refresh(for: settings)                 // AI off
        settings.aiEnabled = true
        await catalog.refresh(for: settings)                 // Claude, no key
        settings.provider = .other
        await catalog.refresh(for: settings)                 // Other, no address

        #expect(asked == 0)
        #expect(catalog.state == .idle)
    }

    @Test func onThisMacTheFirstModelFoundIsUsedUntilAnotherIsPicked() async {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.provider = .local
        let found = self.found
        let catalog = ModelCatalog(fetch: { found })
        #expect(settings.isReady == false)

        await catalog.refresh(for: settings)

        #expect(catalog.state == .loaded(found))
        #expect(settings.talkModel == "gemma-test")
        #expect(settings.digestModel == "gemma-test")
        #expect(settings.isReady)

        // A choice the user made is kept, as long as that model is still there.
        settings.talkModel = "qwen-test:8b"
        await catalog.refresh(for: settings)
        #expect(settings.talkModel == "qwen-test:8b")
    }

    @Test func aModelRemovedFromOllamaIsReplaced() async {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.provider = .local
        settings.talkModel = "one-that-was-deleted"
        settings.digestModel = "qwen-test:8b"
        let found = self.found

        await ModelCatalog(fetch: { found }).refresh(for: settings)

        #expect(settings.talkModel == "gemma-test")
        #expect(settings.digestModel == "qwen-test:8b")
    }

    @Test func forOtherServicesNoModelIsChosenOnTheUsersBehalf() async {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.provider = .openai
        settings.saveAPIKey("made-up-openai-key")
        let found = self.found

        await ModelCatalog(fetch: { found }).refresh(for: settings)

        #expect(settings.talkModel == "")
        #expect(settings.setupGap == .model)
    }

    @Test func aListThatCannotBeFetchedSaysWhyInTheNameOfTheService() async {
        let box = SettingsBox()
        let settings = box.settings()
        settings.aiEnabled = true
        settings.provider = .local
        let catalog = ModelCatalog(fetch: { throw LLMError.offline })

        await catalog.refresh(for: settings)

        #expect(catalog.state == .failed(.offline))
        #expect(catalog.choices.isEmpty)

        catalog.clear()
        #expect(catalog.state == .idle)
    }
}

// MARK: - Talk follows the chosen service

@MainActor
@Suite struct TalkWithOtherServicesTests {

    @Test func talkIsOfferedForAModelOnThisMacWithoutAnyKey() {
        let sandbox = TalkSandbox(aiOn: true, hasKey: false)
        let controller = sandbox.controller(FakeProvider())
        #expect(controller.isAvailable == false)

        sandbox.settings.provider = .local
        #expect(controller.isAvailable == false)       // no model chosen yet
        sandbox.settings.talkModel = "local-test"
        #expect(controller.isAvailable)

        // Choosing a service that is not set up takes Talk away at once, and closes it.
        controller.toggle()
        #expect(controller.isOn)
        sandbox.settings.provider = .openai
        #expect(controller.isAvailable == false)
        #expect(controller.isOn == false)
    }

    @Test func aFailureIsDescribedInTheNameOfTheServiceInUse() async {
        let sandbox = TalkSandbox(aiOn: true, hasKey: false)
        sandbox.settings.provider = .local
        sandbox.settings.talkModel = "local-test"
        let provider = FakeProvider([.fail(.offline)])
        let controller = sandbox.controller(provider)
        controller.toggle()
        controller.show(entry: TalkFixtures.entry)
        await controller.replyTask?.value

        #expect(provider.requests.first?.model == "local-test")
        #expect(controller.transcript.notice == "Couldn't reach Ollama. Open the Ollama app, then try again.")
    }
}
