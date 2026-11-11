//
//  MemoryEngineTests.swift
//  freewriteTests
//
//  Checks the background engine with a pretend AI, a throwaway journal folder
//  and a clock the test controls: when an entry counts as settled, that
//  unchanged entries are never sent twice, that failures are quiet, and that
//  nothing is read or sent while memory is off.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct MemoryEngineTests {

    private func summary(of engine: MemoryEngine) async -> MemorySummary {
        await MainActor.run { engine.status.summary }
    }

    // MARK: - Off means off

    @Test func whileMemoryIsOffNothingIsReadOrSent() async {
        let sandbox = MemorySandbox()
        sandbox.enabled = false
        sandbox.writeEntry(MemoryWeek.monday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .off)
        #expect(await engine.runPass(includeFresh: true) == .off)
        await engine.rebuild()

        #expect(provider.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sandbox.store.folder.path))
    }

    // MARK: - Digesting a settled entry

    @Test func aSettledEntryIsDigestedIntoNotesWithEvidence() async throws {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 1))

        // What was sent: the memory model, the entry, the shape to reply in.
        let request = try #require(provider.requests.first)
        #expect(request.model == "model-for-memory")
        #expect(request.system == Prompts.digestSystem)
        #expect(request.jsonSchema == DigestSchema.data)
        #expect(request.retryIfDeclined)
        #expect(request.messages.first?.text.contains("I said yes to everything she asked") == true)
        #expect(request.messages.first?.text.hasPrefix("People already in memory: (none yet)\nTopics already in memory: (none yet)\nFeelings already in memory: (none yet)\n\nEntry written on Monday 2 November 2026:\n<entry>\n") == true)

        // What was written: the lasting things as notes, with nothing in the AI's words about them.
        let memory = sandbox.store.loadSnapshot()
        #expect(Set(memory.thoughts.keys) == ["meera", "the-launch"])
        #expect(memory.thoughts.values.allSatisfy { $0.summary.isEmpty && $0.timeline.isEmpty })
        #expect(memory.profile.isEmpty)

        // And the day's own lines, kept with the entry's digest.
        let digest = try #require(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id))
        #expect(digest.textHash == MemoryEngine.fingerprint(MemoryWeek.monday.text))
        #expect(digest.entryDate == "2026-11-02")
        #expect(digest.model == "model-for-memory")
        #expect(digest.thoughts == ["meera", "the-launch"])
        #expect(digest.isJournalShaped)
        #expect(digest.summary.isEmpty)
        #expect(digest.lines?.map(\.kind) == [.felt, .felt, .happened, .toldYourself])
        #expect(digest.lines?.first == DayLine(kind: .felt, quote: "Couldn’t sleep again.", word: "Couldn't sleep", tone: .unpleasant))
        #expect(digest.rejected == [EntryDigest.Rejection(item: "feeling", reason: "Its quote is not in the entry.")])
        #expect(digest.inputTokens == 1200)
        #expect(digest.failed == false)

        let status = await summary(of: engine)
        #expect(status.hasOlderShape == false)
        #expect(status.thoughts == 2)
        #expect(status.digestedEntries == 1)
        #expect(status.waitingEntries == 0)
        #expect(status.isWorking == false)
        #expect(status.problem == nil)
    }

    @Test func laterEntriesAreGivenTheThoughtsAlreadyInMemory() async throws {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply]), .reply([MemoryWeek.wednesdayReply])])

        #expect(await sandbox.engine(provider).runPass() == .finished(digested: 2))

        // Oldest first, and the second request carries the names found by the first, so the
        // same person, topic or feeling is not given a second name.
        let second = try #require(provider.requests.last?.messages.first?.text)
        #expect(second.contains("People already in memory: Meera\n"))
        #expect(second.contains("Topics already in memory: the launch\n"))
        #expect(second.contains("Feelings already in memory: Couldn't sleep (unpleasant), felt sick (unpleasant)\n"))
        #expect(second.contains("Went for a run before work"))
        // Only names are handed on: nothing else from the earlier entry.
        #expect(!second.contains("I said yes to everything she asked"))
        #expect(!second.contains("the call with Meera"))
    }

    // MARK: - When an entry counts as settled

    @Test func anEntryBeingTypedIsNeverDigested() async {
        let sandbox = MemorySandbox()
        // Old entry, but edited ten seconds ago: someone is typing in it.
        sandbox.writeEntry(MemoryWeek.monday, quietFor: 10)
        sandbox.writeEntry(MemoryWeek.sunday, quietFor: 10)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(await engine.runPass(includeFresh: true) == .finished(digested: 0))
        #expect(provider.requests.isEmpty)
        #expect(await summary(of: engine).waitingEntries == 2)
    }

    @Test func todaysEntryWaitsUntilItHasBeenLeftAloneForTenMinutes() async {
        let sandbox = MemorySandbox(now: MemoryWeek.day(8, hour: 9, minute: 30))
        // Sunday's entry, started today, last edited five minutes ago, and nothing newer.
        sandbox.writeEntry(MemoryWeek.sunday, quietFor: 300)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(provider.requests.isEmpty)

        sandbox.clock = sandbox.clock.addingTimeInterval(360)
        #expect(await engine.runPass() == .finished(digested: 1))
        #expect(provider.requests.count == 1)
    }

    @Test func switchingTalkOnSettlesTodaysEntryStraightAway() async {
        let sandbox = MemorySandbox(now: MemoryWeek.day(8, hour: 9, minute: 30))
        sandbox.writeEntry(MemoryWeek.sunday, quietFor: 300)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])

        #expect(await sandbox.engine(provider).runPass(includeFresh: true) == .finished(digested: 1))
    }

    @Test func startingANewEntrySettlesTheOneBefore() async {
        let sandbox = MemorySandbox(now: MemoryWeek.day(8, hour: 9, minute: 30))
        // Two entries from today, both edited two minutes ago. Only the older one has settled.
        let earlier = MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(8, hour: 7), text: "An earlier entry from this morning, long enough to count.")
        sandbox.writeEntry(earlier, quietFor: 120)
        sandbox.writeEntry(MemoryWeek.sunday, quietFor: 120)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])

        #expect(await sandbox.engine(provider).runPass() == .finished(digested: 1))
        #expect(provider.requests.first?.messages.first?.text.contains("An earlier entry from this morning") == true)
    }

    @Test func aChangeOfDaySettlesYesterdaysEntry() async {
        let sandbox = MemorySandbox(now: MemoryWeek.day(9, hour: 0, minute: 5))
        // Started yesterday morning, edited two minutes ago, nothing newer.
        sandbox.writeEntry(MemoryWeek.sunday, quietFor: 120)
        let provider = FakeProvider([.reply([DigestJSON.reply()])])

        #expect(await sandbox.engine(provider).runPass() == .finished(digested: 1))
    }

    // MARK: - Unchanged entries are never sent twice

    @Test func anUnchangedEntryIsNotSentAgain() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply])])
        let engine = sandbox.engine(provider)

        await engine.runPass()
        await engine.runPass()
        await engine.runPass(includeFresh: true)

        // Even a brand-new engine (as after relaunching the app) leaves it alone.
        await sandbox.engine(provider).runPass()

        #expect(provider.requests.count == 1)
    }

    @Test func anEditedEntryIsDigestedAgainAndItsOldLinesAreReplaced() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let revised = DigestJSON.reply(people: [DigestJSON.named("Meera", "Meera was kind about it in the end.")])
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply]), .reply([revised])])
        let engine = sandbox.engine(provider)
        await engine.runPass()

        sandbox.writeEntry(MemoryWeek.monday, text: "I rewrote this one. Meera was kind about it in the end.", quietFor: 1800)
        #expect(await engine.runPass() == .finished(digested: 1))

        #expect(provider.requests.count == 2)
        let memory = sandbox.store.loadSnapshot()
        #expect(Set(memory.thoughts.keys) == ["meera"])
        #expect(memory.thoughts["meera"]?.evidence.map(\.quote) == ["Meera was kind about it in the end."])
        #expect(!sandbox.thoughtFileExists("the-launch"))
        // The day's lines are replaced too.
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id)?.lines == [])
    }

    @Test func aDeletedEntryTakesItsLinesOutOfMemory() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply]), .reply([MemoryWeek.wednesdayReply])])
        let engine = sandbox.engine(provider)
        await engine.runPass()

        sandbox.deleteEntry(MemoryWeek.monday)
        await engine.runPass()

        #expect(provider.requests.count == 2)
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id) == nil)
        #expect(Set(sandbox.store.loadSnapshot().thoughts.keys) == ["the-launch", "arjun", "the-friday-review", "a-run-before-work"])
    }

    @Test func theWelcomeGuideVideoEntriesAndEmptyPagesAreSkipped() async throws {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(1), text: MemorySandbox.welcomeText))
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(2), text: "Video Entry"))
        sandbox.writeEntry(MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(3), text: "\n\n   \n"))

        // A text file that sits beside a video is a video entry, whatever it says.
        let withVideo = MemoryWeek.Entry(id: UUID(), startedAt: MemoryWeek.day(4), text: "Some words beside a recording.")
        let url = sandbox.writeEntry(withVideo)
        let base = url.deletingPathExtension().lastPathComponent
        let videoFolder = sandbox.root.appendingPathComponent("Videos").appendingPathComponent(base)
        try FileManager.default.createDirectory(at: videoFolder, withIntermediateDirectories: true)
        try Data().write(to: videoFolder.appendingPathComponent("\(base).mov"))

        // Files that are not entries at all.
        try "notes".write(to: sandbox.root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let provider = FakeProvider()
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(provider.requests.isEmpty)
        #expect(await engine.entriesToRebuild() == 0)
    }

    // MARK: - Switching memory on does not send the back catalogue

    @Test func entriesFromBeforeMemoryWasSwitchedOnWaitForARebuild() async {
        let sandbox = MemorySandbox()
        sandbox.enabledSince = MemoryWeek.day(5)
        // Monday was last edited before the switch; Friday after it.
        sandbox.writeEntry(MemoryWeek.monday, quietFor: sandbox.clock.timeIntervalSince(MemoryWeek.day(3)))
        sandbox.writeEntry(MemoryWeek.friday, quietFor: sandbox.clock.timeIntervalSince(MemoryWeek.day(7)))
        let provider = FakeProvider([.reply([DigestJSON.reply()]), .reply([MemoryWeek.mondayReply]), .reply([DigestJSON.reply()])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 1))
        #expect(provider.requests.first?.messages.first?.text.contains("pricing page") == true)
        #expect(await summary(of: engine).waitingEntries == 0)

        // A rebuild is the explicit way to bring older entries in.
        #expect(await engine.entriesToRebuild() == 2)
        await engine.rebuild()
        #expect(provider.requests.count == 3)
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id) != nil)
    }

    // MARK: - Failures are quiet

    @Test func anAnswerThatCannotBeUsedIsNotAskedForAgain() async throws {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let provider = FakeProvider([.reply(["Sorry, here are my thoughts in prose instead."]), .reply([MemoryWeek.mondayReply])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 1))
        await engine.runPass()
        #expect(provider.requests.count == 1)

        let digest = try #require(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id))
        #expect(digest.failed)
        #expect(digest.failureReason == "The reply was not valid JSON.")
        #expect(sandbox.store.loadSnapshot().thoughts.isEmpty)
        #expect(await summary(of: engine).digestedEntries == 0)

        // It is tried again only once the entry itself changes.
        sandbox.writeEntry(MemoryWeek.monday, text: MemoryWeek.monday.text + "\n\nOne more line.", quietFor: 1800)
        await engine.runPass()
        #expect(provider.requests.count == 2)
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id)?.failed == false)
    }

    @Test func aDeclinedEntryIsMarkedAndTheRestCarryOn() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        let provider = FakeProvider([.fail(.refused), .reply([DigestJSON.reply(selfTalk: ["The launch date moved again."])])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 2))

        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id)?.failed == true)
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.wednesday.id)?.lines == [DayLine(kind: .toldYourself, quote: "The launch date moved again.")])
        #expect(await summary(of: engine).problem == nil)
    }

    @Test func noNetworkStopsThePassShowsOneLineAndIsTriedAgainLater() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        let provider = FakeProvider([.fail(.offline), .reply([MemoryWeek.mondayReply]), .reply([MemoryWeek.wednesdayReply])])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(provider.requests.count == 1)
        #expect(await summary(of: engine).problem == LLMError.offline.userMessage)
        #expect(sandbox.store.loadDigest(entryID: MemoryWeek.monday.id) == nil)

        // Straight away: it waits. Five minutes later: it carries on from where it stopped.
        #expect(await engine.runPass() == .paused)
        sandbox.clock = sandbox.clock.addingTimeInterval(301)
        #expect(await engine.runPass() == .finished(digested: 2))
        #expect(await summary(of: engine).problem == nil)
    }

    @Test func aBadKeyIsReportedPlainly() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        let engine = sandbox.engine(FakeProvider([.fail(.invalidKey)]))

        await engine.runPass()

        #expect(await summary(of: engine).problem == LLMError.invalidKey.userMessage)
    }

    @Test func theDailyLimitStopsBackgroundWorkUntilTomorrow() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        sandbox.writeEntry(MemoryWeek.friday)
        let provider = FakeProvider([.reply([DigestJSON.reply()]), .reply([DigestJSON.reply()]), .reply([DigestJSON.reply()])])
        var limits = MemorySandbox.quietLimits
        limits.dailyRequests = 2
        let engine = sandbox.engine(provider, limits: limits)

        #expect(await engine.runPass() == .finished(digested: 2))
        #expect(provider.requests.count == 2)
        #expect(await summary(of: engine).problem?.contains("limit of 2") == true)

        await engine.runPass()
        #expect(provider.requests.count == 2)

        sandbox.clock = sandbox.clock.addingTimeInterval(24 * 3600)
        #expect(await engine.runPass() == .finished(digested: 1))
        #expect(provider.requests.count == 3)
    }

    // MARK: - Rebuild and forget

    @Test func aRebuildGivesTheSameMemoryAndKeepsTheUsersFixes() async throws {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let script = MemoryWeek.replies.map { FakeProvider.Step.reply([$0]) }
        let provider = FakeProvider(script + script)
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 4))
        let first = sandbox.store.loadSnapshot()
        #expect(first.thoughts.count == 8)

        // The user's fixes and a hand-written note live in the memory folder too.
        try "{\"renames\": []}".write(to: sandbox.store.pinsURL, atomically: true, encoding: .utf8)
        let handWritten = sandbox.store.thoughtURL("my-own-note")
        try "Not a thought note.".write(to: handWritten, atomically: true, encoding: .utf8)

        #expect(await engine.entriesToRebuild() == 4)
        await engine.rebuild()

        #expect(provider.requests.count == 8)
        var rebuilt = sandbox.store.loadSnapshot()
        #expect(rebuilt.unreadableIDs == ["my-own-note"])
        rebuilt.unreadableIDs = []
        #expect(rebuilt == first)
        #expect(FileManager.default.fileExists(atPath: sandbox.store.pinsURL.path))
        #expect(FileManager.default.fileExists(atPath: handWritten.path))
    }

    @Test func aRebuildIsNotHeldBackByTheDailyLimit() async {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        var limits = MemorySandbox.quietLimits
        limits.dailyRequests = 1
        let provider = FakeProvider(MemoryWeek.replies.map { .reply([$0]) })

        await sandbox.engine(provider, limits: limits).rebuild()

        #expect(provider.requests.count == 4)
    }

    @Test func forgettingEverythingDeletesMemoryAndLeavesEntriesAlone() async {
        let sandbox = MemorySandbox()
        let entryURL = sandbox.writeEntry(MemoryWeek.monday)
        let engine = sandbox.engine(FakeProvider([.reply([MemoryWeek.mondayReply])]))
        await engine.runPass()
        #expect(FileManager.default.fileExists(atPath: sandbox.store.folder.path))

        await engine.forgetEverything()

        #expect(!FileManager.default.fileExists(atPath: sandbox.store.folder.path))
        #expect(FileManager.default.fileExists(atPath: entryURL.path))
        #expect(await summary(of: engine) == MemorySummary())
    }

    // MARK: - The shape of a journal

    @Test func theWholeWeekIsKeptAsLastingThingsAndTheDaysOwnLines() async throws {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let engine = sandbox.engine(FakeProvider(MemoryWeek.replies.map { .reply([$0]) }))

        #expect(await engine.runPass() == .finished(digested: 4))

        // The engine and the made-up week read by hand agree, file for file.
        let expected = try MemoryWeek.read()
        #expect(sandbox.store.loadSnapshot() == expected.memory)
        for digest in expected.digests {
            let saved = try #require(sandbox.store.loadDigest(entryID: digest.entryID))
            #expect(saved.lines == digest.lines)
            #expect(saved.thoughts == digest.thoughts)
        }

        let memory = sandbox.store.loadSnapshot()
        let kinds = Dictionary(grouping: memory.thoughts.values, by: \.kind).mapValues { $0.map(\.label).sorted() }
        #expect(kinds[.person] == ["Arjun", "Meera"])
        #expect(kinds[.topic] == ["the Friday review", "the launch", "the pricing page"])
        #expect(kinds[.helped] == ["a run before work"])
        #expect(kinds[.open] == ["I said I needed to think about it", "Need to tell her by Tuesday"])
        // The profile is a few counted lines, not a paragraph about the writer.
        #expect(memory.profile == """
        Most written about in the last month: Meera (3 entries), the launch (2 entries), the pricing page (2 entries).
        Still open: 2 things, the oldest since Friday 6 November 2026.
        They wrote that these helped: a run before work.
        """)
    }

    @Test func aFeelingNamedInTheSameWordsOnTwoDaysBecomesAThoughtAndGoesWhenADayGoes() async throws {
        let sandbox = MemorySandbox(now: MemoryWeek.day(24, hour: 21))
        let first = MemoryWeek.Entry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, startedAt: MemoryWeek.day(11), text: "Tanvi said I've been distant. She's right. I'm tired all the time.")
        let second = MemoryWeek.Entry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!, startedAt: MemoryWeek.day(22), text: "I'm so tired of all of it. I haven't told anyone that.")
        sandbox.writeEntry(first)
        sandbox.writeEntry(second)
        let provider = FakeProvider([
            .reply([DigestJSON.reply(people: [DigestJSON.named("Tanvi", "Tanvi said I've been distant.")], feelings: [DigestJSON.felt("tired", "unpleasant", "I'm tired all the time")])]),
            .reply([DigestJSON.reply(feelings: [DigestJSON.felt("tired", "unpleasant", "I'm so tired of all of it.")])]),
        ])
        let engine = sandbox.engine(provider)

        #expect(await engine.runPass() == .finished(digested: 2))

        // The second entry was told which feelings the writer had already named.
        #expect(provider.requests.last?.messages.first?.text.contains("Feelings already in memory: tired (unpleasant)") == true)
        let tired = try #require(sandbox.store.loadSnapshot().thoughts["felt-tired"])
        #expect(tired.kind == .feeling)
        #expect(tired.label == "tired")
        #expect(tired.evidence.map(\.quote) == ["I'm tired all the time", "I'm so tired of all of it."])
        // The second day touched no person or topic, only the feeling.
        #expect(sandbox.store.loadDigest(entryID: second.id)?.thoughts == ["felt-tired"])

        // Delete one of the two days: the feeling goes back to being a line on the other.
        sandbox.deleteEntry(second)
        await engine.runPass()
        #expect(Set(sandbox.store.loadSnapshot().thoughts.keys) == ["tanvi"])
        #expect(!sandbox.thoughtFileExists("felt-tired"))
    }

    @Test func entriesReadBeforeM14AreLeftAsTheyWereAndSettingsIsTold() async throws {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        // A memory folder as an earlier version left it.
        let older = try MemoryWeek.built()
        try sandbox.store.write(older.memory, replacing: MemorySnapshot())
        for digest in older.digests {
            try sandbox.store.saveDigest(digest)
        }
        let provider = FakeProvider(MemoryWeek.replies.map { .reply([$0]) })
        let engine = sandbox.engine(provider)

        // Nothing is sent by itself: the entries have not changed.
        #expect(await engine.runPass() == .finished(digested: 0))
        #expect(provider.requests.isEmpty)
        #expect(sandbox.store.loadSnapshot() == older.memory)
        #expect(await summary(of: engine).hasOlderShape)
        await engine.refreshStatus()
        #expect(await summary(of: engine).hasOlderShape)

        // A rebuild brings them into the new shape.
        await engine.rebuild()
        #expect(provider.requests.count == 4)
        #expect(await summary(of: engine).hasOlderShape == false)
        #expect(sandbox.store.loadSnapshot() == (try MemoryWeek.read().memory))
    }

    @Test func theSameTextAlwaysHasTheSameFingerprint() {
        #expect(MemoryEngine.fingerprint("hello") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(MemoryEngine.fingerprint("hello") != MemoryEngine.fingerprint("hello "))
    }
}
