//
//  MemoryTidyTests.swift
//  freewriteTests
//
//  Checks the weekly tidy: its reply is read strictly, each proposal is
//  checked before it changes anything, the user's fixes are obeyed, and it
//  runs about once a week or on request. Uses the made-up week of entries.
//

import Foundation
import Testing
@testable import freewrite

/// Builds the JSON a tidy reply is made of.
enum TidyJSON {
    static func reply(merges: [[String: Any]] = [], retire: [String] = []) -> String {
        let object: [String: Any] = ["merges": merges, "retire": retire]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

@Suite struct TidyParserTests {

    @Test func readsAFullReply() throws {
        let result = try TidyParser.parse(TidyJSON.reply(merges: [["from": "pricing", "into": "the-pricing-page"]], retire: ["arjun"]))

        #expect(result.merges == [TidyResult.Merge(from: "pricing", into: "the-pricing-page")])
        #expect(result.retire == ["arjun"])
    }

    @Test func readsAnEmptyButValidReply() throws {
        #expect(try TidyParser.parse(TidyJSON.reply()) == TidyResult())
    }

    @Test(arguments: [
        "not json",
        "{}",
        "{\"merges\":[]}",
        "{\"merges\":[],\"retire\":[],\"mood\":\"low\"}",
        "{\"merges\":[{\"from\":\"a\"}],\"retire\":[]}",
        "{\"merges\":[],\"retire\":[7]}",
        // The tidy no longer names patterns or writes a profile, and a reply that tries to is refused.
        "{\"merges\":[],\"retire\":[],\"patterns\":[],\"links\":[],\"profile\":null}",
        "{\"merges\":[],\"retire\":[],\"profile\":\"They tend to agree too fast.\"}",
    ])
    func refusesAnythingThatIsNotExactlyTheExpectedShape(reply: String) {
        #expect(throws: DigestParseError.self) {
            _ = try TidyParser.parse(reply)
        }
    }

    @Test func theSchemaMatchesWhatTheParserExpects() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: TidySchema.data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["merges", "retire"])

        var objectsChecked = 0
        func check(_ node: Any) {
            guard let dictionary = node as? [String: Any] else { return }
            if dictionary["type"] as? String == "object" {
                let fields = dictionary["properties"] as? [String: Any] ?? [:]
                #expect(dictionary["additionalProperties"] as? Bool == false)
                #expect(Set(dictionary["required"] as? [String] ?? []) == Set(fields.keys))
                objectsChecked += 1
            }
            dictionary.values.forEach(check)
        }
        check(schema)

        // The reply and a merge.
        #expect(objectsChecked == 2)
    }

    @Test func theInstructionsAskForNothingInTheAIsOwnWords() {
        #expect(!Prompts.tidySystem.contains("pattern"))
        #expect(!Prompts.tidySystem.contains("profile"))
        #expect(Prompts.tidySystem.contains("Never merge two different people."))
    }
}

@Suite struct MemoryTidierTests {

    private func tidy(
        _ reply: String,
        _ memory: inout MemorySnapshot,
        pins: Pins = Pins(),
        today: String = "2026-11-30"
    ) throws -> MemoryTidier.Outcome {
        MemoryTidier.apply(try TidyParser.parse(reply), to: &memory, pins: pins, today: today)
    }

    /// The week's memory plus a topic that is the pricing page under another name.
    private func weekWithADuplicate() throws -> MemorySnapshot {
        var memory = try MemoryWeek.read().memory
        memory.thoughts["pricing"] = Thought(
            id: "pricing",
            label: "pricing",
            kind: .topic,
            evidence: [Evidence(entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Need to tell her by Tuesday.")]
        )
        return memory
    }

    // MARK: - Duplicates

    @Test func aDuplicateIsFoldedIntoTheThoughtItRepeats() throws {
        var memory = try weekWithADuplicate()

        let outcome = try tidy(TidyJSON.reply(merges: [["from": "pricing", "into": "the-pricing-page"]]), &memory)

        #expect(outcome.merged == 1)
        #expect(outcome.rejected.isEmpty)
        #expect(memory.thoughts["pricing"] == nil)
        let kept = try #require(memory.thoughts["the-pricing-page"])
        #expect(kept.aliases.contains("pricing"))
        #expect(kept.evidence.map(\.quote).contains("Need to tell her by Tuesday."))
        #expect(outcome.line == "merged 1")
    }

    @Test func aMergeIsRefusedWhenItMakesNoSenseOrTouchesAThoughtTheUserRenamed() throws {
        var memory = try weekWithADuplicate()
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "pricing", to: "What we charge"), to: &memory, pins: &pins)
        let before = memory

        let outcome = try tidy(TidyJSON.reply(merges: [
            ["from": "pricing", "into": "the-pricing-page"],
            ["from": "meera", "into": "meera"],
            ["from": "made-up", "into": "meera"],
        ]), &memory, pins: pins)

        #expect(outcome.merged == 0)
        #expect(outcome.rejected.map(\.reason) == [
            "You renamed or linked this thought.",
            "It merged a thought into itself.",
            "It named a thought that is not in memory.",
        ])
        #expect(memory == before)
    }

    @Test func aPersonIsNeverFoldedIntoATopicAndOpenThingsAreLeftAlone() throws {
        var memory = try MemoryWeek.read().memory
        let before = memory

        let outcome = try tidy(TidyJSON.reply(merges: [
            ["from": "arjun", "into": "the-friday-review"],
            ["from": "the-launch", "into": "meera"],
            ["from": "need-to-tell-her-by-tuesday", "into": "the-pricing-page"],
            ["from": "the-pricing-page", "into": "i-said-i-needed-to-think-about-it"],
        ]), &memory)

        #expect(outcome.merged == 0)
        #expect(outcome.rejected.map(\.reason) == [
            "A person is not folded into something that is not a person.",
            "A person is not folded into something that is not a person.",
            "Feelings and open things are left as you wrote them.",
            "Feelings and open things are left as you wrote them.",
        ])
        #expect(memory == before)
    }

    // MARK: - One-offs

    @Test func onlyRealOneOffsAreRetiredWhateverTheModelSuggests() throws {
        var memory = try MemoryWeek.read().memory

        // "Arjun" and "the Friday review" were each seen once, on 4 November. "Meera" recurs.
        let outcome = try tidy(TidyJSON.reply(retire: ["the-friday-review", "arjun", "meera", "nothing-like-this"]), &memory)

        #expect(outcome.retired == 2)
        #expect(memory.thoughts["the-friday-review"] == nil)
        #expect(memory.thoughts["arjun"] == nil)
        #expect(memory.thoughts["meera"] != nil)
        #expect(outcome.rejected.map(\.reason) == ["It is not a one-off.", "It named a thought that is not in memory."])
        #expect(outcome.line == "retired 2")
    }

    @Test func whatHelpedAndWhatIsStillOpenAreKeptEvenWhenSeenOnce() throws {
        var memory = try MemoryWeek.read().memory

        let outcome = try tidy(TidyJSON.reply(retire: ["a-run-before-work", "need-to-tell-her-by-tuesday"]), &memory)

        #expect(outcome.retired == 0)
        #expect(memory.thoughts["a-run-before-work"] != nil)
        #expect(memory.thoughts["need-to-tell-her-by-tuesday"] != nil)
        #expect(outcome.rejected.allSatisfy { $0.reason == "It is kept even when seen once." })
    }

    @Test func aRecentOneOffIsKeptBecauseItMayStillReturn() throws {
        var memory = try MemoryWeek.read().memory

        // Ten days after it was written is too soon.
        let outcome = try tidy(TidyJSON.reply(retire: ["arjun"]), &memory, today: "2026-11-14")

        #expect(outcome.retired == 0)
        #expect(memory.thoughts["arjun"] != nil)
        #expect(outcome.rejected.map(\.reason) == ["It is not a one-off."])
    }

    @Test func aOneOffTheUserRenamedOrLinkedIsNeverRetired() throws {
        var memory = try MemoryWeek.read().memory
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "the-friday-review", to: "Friday reviews"), to: &memory, pins: &pins)
        MemoryFixes.apply(.addLink(from: "arjun", to: "meera", reason: "works with"), to: &memory, pins: &pins)

        let outcome = try tidy(TidyJSON.reply(retire: ["the-friday-review", "arjun"]), &memory, pins: pins)

        #expect(outcome.retired == 0)
        #expect(memory.thoughts["the-friday-review"]?.label == "Friday reviews")
        #expect(memory.thoughts["arjun"] != nil)
        #expect(outcome.rejected.allSatisfy { $0.reason == "You renamed or linked this thought." })
    }

    @Test func aMemoryBuiltBeforeM14IsTidiedTheSameWay() throws {
        var memory = try MemoryWeek.built().memory

        // "Running" (an idea) and "Arjun" were each seen once; the older kinds are not special.
        let outcome = try tidy(TidyJSON.reply(
            merges: [["from": "the-pricing-page", "into": "the-launch"]],
            retire: ["running", "arjun", "meera"]
        ), &memory)

        #expect(outcome.merged == 1)
        #expect(outcome.retired == 2)
        #expect(memory.thoughts["the-pricing-page"] == nil)
        #expect(memory.thoughts["running"] == nil)
        #expect(outcome.line == "merged 1, retired 2")
        #expect(MemoryTidier.Outcome().line == "nothing needed changing")
    }
}

@Suite struct TidyScheduleTests {

    private func summary(of engine: MemoryEngine) async -> MemorySummary {
        await MainActor.run { engine.status.summary }
    }

    /// A sandbox with the made-up week already in memory, in the shape of a journal.
    private func weekSandbox(without dropped: String? = nil) throws -> MemorySandbox {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        var read = try MemoryWeek.read()
        if let dropped {
            read.memory.thoughts[dropped] = nil
        }
        try sandbox.store.write(read.memory, replacing: MemorySnapshot())
        for digest in read.digests {
            try sandbox.store.saveDigest(digest)
        }
        return sandbox
    }

    private var lowBar: MemoryLimits {
        var limits = MemorySandbox.quietLimits
        limits.tidyMinimumThoughts = 2
        return limits
    }

    @Test func aTidyOnRequestSendsAllOfMemoryOnceAndAppliesTheResult() async throws {
        let sandbox = try weekSandbox()
        sandbox.clock = MemoryWeek.day(30)
        let provider = FakeProvider([.reply([TidyJSON.reply(retire: ["arjun"])])])
        let engine = sandbox.engine(provider, limits: lowBar)

        let outcome = await engine.tidy(force: true)

        #expect(outcome?.retired == 1)
        #expect(provider.requests.count == 1)

        let request = try #require(provider.requests.first)
        #expect(request.system == Prompts.tidySystem)
        #expect(request.jsonSchema == TidySchema.data)
        #expect(request.model == "model-for-memory")
        let message = try #require(request.messages.first?.text)
        #expect(message.hasPrefix("Today is Monday 30 November 2026."))
        #expect(message.contains("- meera | Meera | person | - | 3 | 2026-11-02 | 2026-11-08"))
        #expect(message.contains("    2026-11-02: \"the call with Meera\""))
        #expect(message.contains("- need-to-tell-her-by-tuesday | Need to tell her by Tuesday | still open | - | 1 | 2026-11-08 | 2026-11-08"))
        #expect(message.contains("- a-run-before-work | a run before work | what helped |"))
        // Nothing in the AI's words about the writer goes with it, because there is none.
        #expect(!message.contains("Profile"))

        let memory = sandbox.store.loadSnapshot()
        #expect(memory.thoughts["arjun"] == nil)
        // The profile is counted by the app, not written by the model.
        #expect(memory.profile == """
        Most written about in the last month: Meera (3 entries), the launch (2 entries), the pricing page (2 entries).
        Still open: 2 things, the oldest since Friday 6 November 2026.
        They wrote that these helped: a run before work.
        """)

        let status = await summary(of: engine)
        #expect(status.lastTidy == "Tidied on Monday 30 November 2026: retired 1.")
        #expect(status.isWorking == false)
        #expect(status.thoughts == 7)
    }

    @Test func leftAloneItRunsAboutOnceAWeek() async throws {
        let sandbox = try weekSandbox()
        let provider = FakeProvider([.reply([TidyJSON.reply()]), .reply([TidyJSON.reply()])])
        let engine = sandbox.engine(provider, limits: lowBar)

        // The first look only starts the clock.
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.isEmpty)

        sandbox.clock = sandbox.clock.addingTimeInterval(6 * 24 * 3600)
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.isEmpty)

        sandbox.clock = sandbox.clock.addingTimeInterval(2 * 24 * 3600)
        #expect(await engine.tidy() != nil)
        #expect(provider.requests.count == 1)

        // And not again until another week has passed.
        sandbox.clock = sandbox.clock.addingTimeInterval(3 * 24 * 3600)
        #expect(await engine.tidy() == nil)
        sandbox.clock = sandbox.clock.addingTimeInterval(5 * 24 * 3600)
        #expect(await engine.tidy() != nil)
        #expect(provider.requests.count == 2)
    }

    @Test func itWaitsUntilMemoryHoldsEnoughThoughts() async throws {
        // The app's own bar is eight thoughts; here memory holds seven.
        let sandbox = try weekSandbox(without: "arjun")
        let provider = FakeProvider()
        let engine = sandbox.engine(provider)

        #expect(sandbox.store.loadSnapshot().thoughts.count == 7)
        #expect(await engine.tidy() == nil)
        sandbox.clock = sandbox.clock.addingTimeInterval(30 * 24 * 3600)
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.isEmpty)
    }

    @Test func withMemoryOffItNeverRuns() async throws {
        let sandbox = try weekSandbox()
        sandbox.enabled = false
        let provider = FakeProvider()
        let engine = sandbox.engine(provider, limits: lowBar)

        #expect(await engine.tidy(force: true) == nil)
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.isEmpty)
    }

    @Test func anAnswerThatCannotBeUsedChangesNothingAndIsNotAskedForAgainStraightAway() async throws {
        let sandbox = try weekSandbox()
        let before = sandbox.store.loadSnapshot()
        let provider = FakeProvider([.reply(["Here is what I noticed, in prose."])])
        let engine = sandbox.engine(provider, limits: lowBar)

        #expect(await engine.tidy(force: true) == nil)

        #expect(sandbox.store.loadSnapshot() == before)
        #expect(await summary(of: engine).lastTidy == "The last tidy couldn't be used, so nothing was changed.")
        #expect(await summary(of: engine).isWorking == false)

        // The week restarts, so it is not retried on the next look.
        sandbox.clock = sandbox.clock.addingTimeInterval(3600)
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.count == 1)
    }

    @Test func noNetworkShowsOneLineAndLeavesTheTidyDue() async throws {
        let sandbox = try weekSandbox()
        sandbox.clock = MemoryWeek.day(30)
        let provider = FakeProvider([.fail(.offline), .reply([TidyJSON.reply(retire: ["arjun"])])])
        let engine = sandbox.engine(provider, limits: lowBar)

        #expect(await engine.tidy(force: true) == nil)
        #expect(await summary(of: engine).problem == LLMError.offline.userMessage)
        #expect(await summary(of: engine).lastTidy == nil)

        #expect(await engine.tidy(force: true) != nil)
        #expect(await summary(of: engine).problem == nil)
        #expect(sandbox.store.loadSnapshot().thoughts["arjun"] == nil)
    }

    @Test func aRebuildEndsWithATidy() async throws {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        sandbox.clock = MemoryWeek.day(30)
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry, quietFor: 3600)
        }
        let script = MemoryWeek.replies.map { FakeProvider.Step.reply([$0]) } + [.reply([TidyJSON.reply(retire: ["arjun"])])]
        let provider = FakeProvider(script)
        var limits = MemoryLimits()
        limits.dailyRequests = 2

        await sandbox.engine(provider, limits: limits).rebuild()

        // Four entries, then the tidy, and neither is held back by the daily limit.
        #expect(provider.requests.count == 5)
        #expect(provider.requests.last?.system == Prompts.tidySystem)
        #expect(sandbox.store.loadSnapshot().thoughts["arjun"] == nil)
    }

    @Test func theTidyObeysFixesMadeWhileItWasRunning() async throws {
        let sandbox = try weekSandbox()
        sandbox.clock = MemoryWeek.day(30)
        let provider = FakeProvider([.reply([TidyJSON.reply(merges: [["from": "the-friday-review", "into": "the-launch"]], retire: ["arjun"])])])
        let store = sandbox.store

        // While the tidy is with the AI, the user renames "the Friday review" on the map.
        provider.onRequest = { _ in
            let before = store.loadSnapshot()
            var memory = before
            var pins = store.loadPins()
            MemoryFixes.apply(.rename(id: "the-friday-review", to: "Friday reviews"), to: &memory, pins: &pins)
            try? store.savePins(pins)
            try? store.write(memory, replacing: before)
        }

        let outcome = await sandbox.engine(provider, limits: lowBar).tidy(force: true)

        let memory = store.loadSnapshot()
        // A thought the user has named is not folded away, and keeps the name they gave it.
        #expect(outcome?.merged == 0)
        #expect(memory.thoughts["the-friday-review"]?.label == "Friday reviews")
        // The rest of the tidy still goes ahead.
        #expect(outcome?.retired == 1)
        #expect(memory.thoughts["arjun"] == nil)
    }
}
