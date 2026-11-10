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
    static func quote(_ entry: MemoryWeek.Entry, _ text: String) -> [String: Any] {
        ["entry_id": entry.id.uuidString, "quote": text]
    }

    static func reply(
        merges: [[String: Any]] = [],
        retire: [String] = [],
        patterns: [[String: Any]] = [],
        links: [[String: Any]] = [],
        profile: String? = nil
    ) -> String {
        let object: [String: Any] = [
            "merges": merges,
            "retire": retire,
            "patterns": patterns,
            "links": links,
            "profile": profile ?? NSNull(),
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// A pattern and a link that each rest on lines from two different entries.
    static let sleepPattern: [String: Any] = [
        "label": "Sleep follows what is unresolved",
        "kind": "theme",
        "summary": "Bad nights tend to follow something left open with Meera.",
        "evidence": [quote(MemoryWeek.monday, "Couldn't sleep again."), quote(MemoryWeek.sunday, "Slept badly.")],
    ]

    static let meeraSleepLink: [String: Any] = [
        "from": "meera",
        "to": "trouble-sleeping",
        "reason": "unsettles",
        "evidence": [
            quote(MemoryWeek.monday, "I keep replaying the call with Meera about the launch."),
            quote(MemoryWeek.sunday, "I kept drafting the reply to Meera in my head"),
        ],
    ]
}

@Suite struct TidyParserTests {

    @Test func readsAFullReply() throws {
        let reply = TidyJSON.reply(
            merges: [["from": "people-pleasing", "into": "saying-yes-under-pressure"]],
            retire: ["arjun"],
            patterns: [TidyJSON.sleepPattern],
            links: [TidyJSON.meeraSleepLink],
            profile: "They are steadier this week."
        )

        let result = try TidyParser.parse(reply)

        #expect(result.merges == [TidyResult.Merge(from: "people-pleasing", into: "saying-yes-under-pressure")])
        #expect(result.retire == ["arjun"])
        #expect(result.patterns.first?.kind == .theme)
        #expect(result.patterns.first?.evidence.count == 2)
        #expect(result.links.first?.reason == "unsettles")
        #expect(result.links.first?.evidence.first?.entryID == MemoryWeek.monday.id.uuidString)
        #expect(result.profile == "They are steadier this week.")
    }

    @Test func readsAnEmptyButValidReply() throws {
        #expect(try TidyParser.parse(TidyJSON.reply()) == TidyResult())
    }

    @Test(arguments: [
        "not json",
        "{}",
        "{\"merges\":[],\"retire\":[],\"patterns\":[],\"links\":[]}",
        "{\"merges\":[],\"retire\":[],\"patterns\":[],\"links\":[],\"profile\":null,\"mood\":\"low\"}",
        "{\"merges\":[{\"from\":\"a\"}],\"retire\":[],\"patterns\":[],\"links\":[],\"profile\":null}",
        "{\"merges\":[],\"retire\":[7],\"patterns\":[],\"links\":[],\"profile\":null}",
        "{\"merges\":[],\"retire\":[],\"patterns\":[{\"label\":\"x\",\"kind\":\"diagnosis\",\"summary\":\"s\",\"evidence\":[]}],\"links\":[],\"profile\":null}",
        "{\"merges\":[],\"retire\":[],\"patterns\":[],\"links\":[{\"from\":\"a\",\"to\":\"b\",\"reason\":\"r\",\"evidence\":[{\"quote\":\"q\"}]}],\"profile\":null}",
    ])
    func refusesAnythingThatIsNotExactlyTheExpectedShape(reply: String) {
        #expect(throws: DigestParseError.self) {
            _ = try TidyParser.parse(reply)
        }
    }

    @Test func theSchemaMatchesWhatTheParserExpects() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: TidySchema.data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["merges", "retire", "patterns", "links", "profile"])

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

        // The reply, a merge, a pattern, a link, and the quote inside a pattern and inside a link.
        #expect(objectsChecked == 6)
    }
}

@Suite struct MemoryTidierTests {

    private let lateNovember = "2026-11-30"

    private func entry(_ id: UUID) -> DigestedEntry? {
        MemoryWeek.entries.first { $0.id == id }.map(MemoryWeek.digested)
    }

    private func tidy(
        _ reply: String,
        _ memory: inout MemorySnapshot,
        pins: Pins = Pins(),
        today: String = "2026-11-30"
    ) throws -> MemoryTidier.Outcome {
        MemoryTidier.apply(try TidyParser.parse(reply), to: &memory, pins: pins, entry: entry, today: today)
    }

    /// The week's memory plus a thought that duplicates "Saying yes under pressure".
    private func weekWithADuplicate() throws -> MemorySnapshot {
        var memory = try MemoryWeek.built().memory
        memory.thoughts["people-pleasing"] = Thought(
            id: "people-pleasing",
            label: "People pleasing",
            kind: .theme,
            summary: "Putting what others want first.",
            evidence: [Evidence(entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Need to tell her by Tuesday.")]
        )
        return memory
    }

    // MARK: - Duplicates

    @Test func aDuplicateIsFoldedIntoTheThoughtItRepeats() throws {
        var memory = try weekWithADuplicate()

        let outcome = try tidy(TidyJSON.reply(merges: [["from": "people-pleasing", "into": "saying-yes-under-pressure"]]), &memory)

        #expect(outcome.merged == 1)
        #expect(outcome.rejected.isEmpty)
        #expect(memory.thoughts["people-pleasing"] == nil)
        let kept = try #require(memory.thoughts["saying-yes-under-pressure"])
        #expect(kept.aliases.contains("People pleasing"))
        #expect(kept.evidence.map(\.quote).contains("Need to tell her by Tuesday."))
        #expect(outcome.line == "merged 1")
    }

    @Test func aMergeIsRefusedWhenItMakesNoSenseOrTouchesAThoughtTheUserRenamed() throws {
        var memory = try weekWithADuplicate()
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "people-pleasing", to: "Putting others first"), to: &memory, pins: &pins)
        let before = memory

        let outcome = try tidy(TidyJSON.reply(merges: [
            ["from": "people-pleasing", "into": "saying-yes-under-pressure"],
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

    // MARK: - One-offs

    @Test func onlyRealOneOffsAreRetiredWhateverTheModelSuggests() throws {
        var memory = try MemoryWeek.built().memory

        // "Running" and "Arjun" were each seen once, on 4 November. "Meera" recurs.
        let outcome = try tidy(TidyJSON.reply(retire: ["running", "arjun", "meera", "nothing-like-this"]), &memory)

        #expect(outcome.retired == 2)
        #expect(memory.thoughts["running"] == nil)
        #expect(memory.thoughts["arjun"] == nil)
        #expect(memory.thoughts["meera"] != nil)
        #expect(outcome.rejected.map(\.reason) == ["It is not a one-off.", "It named a thought that is not in memory."])
    }

    @Test func aRecentOneOffIsKeptBecauseItMayStillReturn() throws {
        var memory = try MemoryWeek.built().memory

        // Ten days after it was written is too soon.
        let outcome = try tidy(TidyJSON.reply(retire: ["running"]), &memory, today: "2026-11-14")

        #expect(outcome.retired == 0)
        #expect(memory.thoughts["running"] != nil)
        #expect(outcome.rejected.map(\.reason) == ["It is not a one-off."])
    }

    @Test func aOneOffTheUserRenamedOrLinkedIsNeverRetired() throws {
        var memory = try MemoryWeek.built().memory
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "running", to: "Morning runs"), to: &memory, pins: &pins)
        MemoryFixes.apply(.addLink(from: "arjun", to: "meera", reason: "works with"), to: &memory, pins: &pins)

        let outcome = try tidy(TidyJSON.reply(retire: ["running", "arjun"]), &memory, pins: pins)

        #expect(outcome.retired == 0)
        #expect(memory.thoughts["running"]?.label == "Morning runs")
        #expect(memory.thoughts["arjun"] != nil)
        #expect(outcome.rejected.allSatisfy { $0.reason == "You renamed or linked this thought." })
    }

    // MARK: - Patterns and links across weeks

    @Test func aPatternNeedsLinesFromTwoEntriesAndKeepsTheEntriesOwnWords() throws {
        var memory = try MemoryWeek.built().memory

        let outcome = try tidy(TidyJSON.reply(patterns: [TidyJSON.sleepPattern]), &memory)

        #expect(outcome.patterns == 1)
        let pattern = try #require(memory.thoughts["sleep-follows-what-is-unresolved"])
        #expect(pattern.kind == .theme)
        #expect(pattern.evidence == [
            Evidence(entryID: MemoryWeek.monday.id, date: "2026-11-02", quote: "Couldn’t sleep again."),
            Evidence(entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Slept badly."),
        ])
    }

    @Test func aPatternWithLinesFromOneEntryOrInventedLinesIsRefused() throws {
        var memory = try MemoryWeek.built().memory
        let before = memory
        let oneEntry: [String: Any] = [
            "label": "Mondays are hard", "kind": "theme", "summary": "s",
            "evidence": [TidyJSON.quote(MemoryWeek.monday, "Couldn't sleep again."), TidyJSON.quote(MemoryWeek.monday, "I said yes to everything she asked")],
        ]
        let invented: [String: Any] = [
            "label": "Dread of Mondays", "kind": "feeling", "summary": "s",
            "evidence": [TidyJSON.quote(MemoryWeek.monday, "Couldn't sleep again."), TidyJSON.quote(MemoryWeek.sunday, "I dread every Monday morning.")],
        ]
        let wrongEntry: [String: Any] = [
            "label": "Coffee", "kind": "idea", "summary": "s",
            "evidence": [TidyJSON.quote(MemoryWeek.monday, "Too much coffee"), ["entry_id": UUID().uuidString, "quote": "Too much coffee"]],
        ]

        let outcome = try tidy(TidyJSON.reply(patterns: [oneEntry, invented, wrongEntry]), &memory)

        #expect(outcome.patterns == 0)
        #expect(outcome.rejected.count == 3)
        #expect(outcome.rejected.allSatisfy { $0.item == "pattern" && $0.reason == "It needs quoted lines from at least 2 entries." })
        #expect(memory == before)
    }

    @Test func aPatternThatAlreadyHasAThoughtAddsToItInsteadOfMakingAnother() throws {
        var memory = try MemoryWeek.built().memory
        var pattern = TidyJSON.sleepPattern
        pattern["label"] = "TROUBLE sleeping!"

        let outcome = try tidy(TidyJSON.reply(patterns: [pattern]), &memory)

        #expect(outcome.patterns == 1)
        #expect(memory.thoughts.count == 7)
        #expect(memory.thoughts["trouble-sleeping"]?.evidence.count == 3)
    }

    @Test func aLinkAcrossWeeksIsAddedWithEachLineItRestsOn() throws {
        var memory = try MemoryWeek.built().memory

        let outcome = try tidy(TidyJSON.reply(links: [TidyJSON.meeraSleepLink]), &memory)

        #expect(outcome.links == 1)
        let links = try #require(memory.thoughts["meera"]?.links.filter { $0.target == "trouble-sleeping" })
        #expect(links.map(\.date) == ["2026-11-02", "2026-11-08"])
        #expect(links.allSatisfy { $0.reason == "unsettles" })
    }

    @Test func aLinkTheUserRemovedOrOneWithThinEvidenceIsRefused() throws {
        var memory = try MemoryWeek.built().memory
        var pins = Pins()
        pins.linksRemoved = [Pins.LinkPin(from: "trouble-sleeping", to: "meera", reason: nil)]
        var thin = TidyJSON.meeraSleepLink
        thin["to"] = "the-launch"
        thin["evidence"] = [TidyJSON.quote(MemoryWeek.monday, "I keep replaying the call with Meera about the launch.")]

        let outcome = try tidy(TidyJSON.reply(links: [TidyJSON.meeraSleepLink, thin]), &memory, pins: pins)

        #expect(outcome.links == 0)
        #expect(outcome.rejected.map(\.reason) == ["You removed this link.", "It needs quoted lines from at least 2 entries."])
        #expect(memory.thoughts["meera"]?.links.isEmpty == true)
    }

    @Test func aDeletedThoughtDoesNotComeBackAsAPattern() throws {
        var memory = try MemoryWeek.built().memory
        var pins = Pins()
        MemoryFixes.apply(.delete(id: "trouble-sleeping"), to: &memory, pins: &pins)
        var pattern = TidyJSON.sleepPattern
        pattern["label"] = "Trouble sleeping"

        let outcome = try tidy(TidyJSON.reply(patterns: [pattern]), &memory, pins: pins)

        #expect(outcome.patterns == 0)
        #expect(memory.thoughts["trouble-sleeping"] == nil)
        #expect(outcome.rejected == [EntryDigest.Rejection(item: "pattern", reason: "You deleted this thought.")])
    }

    // MARK: - Profile and summary

    @Test func theProfileIsRefreshedAndTheSummaryLineSaysWhatHappened() throws {
        var memory = try weekWithADuplicate()

        let outcome = try tidy(TidyJSON.reply(
            merges: [["from": "people-pleasing", "into": "saying-yes-under-pressure"]],
            retire: ["running"],
            patterns: [TidyJSON.sleepPattern],
            links: [TidyJSON.meeraSleepLink],
            profile: "They are steadier this week."
        ), &memory)

        #expect(memory.profile == "They are steadier this week.")
        #expect(outcome.line == "merged 1, retired 1, 1 pattern across weeks, 1 new link, refreshed the profile")
        #expect(MemoryTidier.Outcome().line == "nothing needed changing")
    }
}

@Suite struct TidyScheduleTests {

    private func summary(of engine: MemoryEngine) async -> MemorySummary {
        await MainActor.run { engine.status.summary }
    }

    /// A sandbox with the made-up week already in memory.
    private func weekSandbox() throws -> MemorySandbox {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let built = try MemoryWeek.built()
        try sandbox.store.write(built.memory, replacing: MemorySnapshot())
        for digest in built.digests {
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
        let provider = FakeProvider([.reply([TidyJSON.reply(retire: ["running"], patterns: [TidyJSON.sleepPattern], profile: "They are steadier this week.")])])
        let engine = sandbox.engine(provider, limits: lowBar)

        let outcome = await engine.tidy(force: true)

        #expect(outcome?.retired == 1)
        #expect(outcome?.patterns == 1)
        #expect(provider.requests.count == 1)

        let request = try #require(provider.requests.first)
        #expect(request.system == Prompts.tidySystem)
        #expect(request.jsonSchema == TidySchema.data)
        #expect(request.model == "model-for-memory")
        let message = try #require(request.messages.first?.text)
        #expect(message.contains("- meera | Meera | person | - | 3 | 2026-11-02 | 2026-11-08 |"))
        #expect(message.contains("quote [\(MemoryWeek.monday.id.uuidString)] 2026-11-02: \"I keep replaying the call with Meera about the launch.\""))
        #expect(message.contains("linked to meera (asked for by), 2026-11-06"))
        #expect(message.contains("- 2026-11-08 [\(MemoryWeek.sunday.id.uuidString)]: A bad night"))

        let memory = sandbox.store.loadSnapshot()
        #expect(memory.thoughts["running"] == nil)
        #expect(memory.thoughts["sleep-follows-what-is-unresolved"] != nil)
        #expect(memory.profile == "They are steadier this week.")

        let status = await summary(of: engine)
        #expect(status.lastTidy == "Tidied on Monday 30 November 2026: retired 1, 1 pattern across weeks, refreshed the profile.")
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
        let sandbox = try weekSandbox()
        let provider = FakeProvider()
        // The app's own bar is eight thoughts; the made-up week has seven.
        let engine = sandbox.engine(provider)

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
        #expect(await summary(of: engine).lastTidy == "The last tidy could not be used, so nothing was changed.")
        #expect(await summary(of: engine).isWorking == false)

        // The week restarts, so it is not retried on the next look.
        sandbox.clock = sandbox.clock.addingTimeInterval(3600)
        #expect(await engine.tidy() == nil)
        #expect(provider.requests.count == 1)
    }

    @Test func noNetworkShowsOneLineAndLeavesTheTidyDue() async throws {
        let sandbox = try weekSandbox()
        let provider = FakeProvider([.fail(.offline), .reply([TidyJSON.reply(profile: "They are steadier this week.")])])
        let engine = sandbox.engine(provider, limits: lowBar)

        #expect(await engine.tidy(force: true) == nil)
        #expect(await summary(of: engine).problem == LLMError.offline.userMessage)
        #expect(await summary(of: engine).lastTidy == nil)

        #expect(await engine.tidy(force: true) != nil)
        #expect(await summary(of: engine).problem == nil)
        #expect(sandbox.store.loadSnapshot().profile == "They are steadier this week.")
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
        let provider = FakeProvider([.reply([TidyJSON.reply(patterns: [TidyJSON.sleepPattern], links: [TidyJSON.meeraSleepLink])])])
        let store = sandbox.store

        // While the tidy is with the AI, the user deletes "Trouble sleeping" on the map.
        provider.onRequest = { _ in
            let before = store.loadSnapshot()
            var memory = before
            var pins = store.loadPins()
            MemoryFixes.apply(.delete(id: "trouble-sleeping"), to: &memory, pins: &pins)
            try? store.savePins(pins)
            try? store.write(memory, replacing: before)
        }

        let outcome = await sandbox.engine(provider, limits: lowBar).tidy(force: true)

        let memory = store.loadSnapshot()
        #expect(memory.thoughts["trouble-sleeping"] == nil)
        #expect(outcome?.links == 0)
        // The pattern itself is a different thought and is allowed.
        #expect(memory.thoughts["sleep-follows-what-is-unresolved"] != nil)
    }
}
