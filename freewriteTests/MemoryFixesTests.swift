//
//  MemoryFixesTests.swift
//  freewriteTests
//
//  Checks the user's manual fixes to memory: what each one changes, that it is
//  recorded in the fixes file, and that it survives later digests and a full
//  rebuild, including when the AI names things differently the second time.
//  Uses the made-up week of entries.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct MemoryFixesTests {

    private func week() throws -> MemorySnapshot {
        try MemoryWeek.built().memory
    }

    // MARK: - Rename

    @Test func renameChangesTheNameKeepsTheOldOneAndIsRecorded() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "  Bad nights "), to: &memory, pins: &pins))

        let thought = try #require(memory.thoughts["trouble-sleeping"])
        #expect(thought.label == "Bad nights")
        #expect(thought.aliases.contains("Trouble sleeping"))
        #expect(pins.renames == [Pins.Rename(id: "trouble-sleeping", label: "Bad nights", names: ["Trouble sleeping"])])
        #expect(pins.pinnedLabel(for: "trouble-sleeping") == "Bad nights")
    }

    @Test func renamingAgainKeepsEveryEarlierNameOnRecord() throws {
        var memory = try week()
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "Bad nights"), to: &memory, pins: &pins)
        MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "Sleep"), to: &memory, pins: &pins)

        #expect(pins.renames.count == 1)
        #expect(pins.renames[0].label == "Sleep")
        #expect(Set(pins.renames[0].names ?? []) == ["Bad nights", "Trouble sleeping"])
        #expect(memory.thoughts["trouble-sleeping"]?.label == "Sleep")
    }

    @Test func aRenameThatMakesNoSenseChangesNothing() throws {
        var memory = try week()
        var pins = Pins()
        let before = memory

        #expect(MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "   "), to: &memory, pins: &pins) == false)
        #expect(MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "Trouble sleeping"), to: &memory, pins: &pins) == false)
        #expect(MemoryFixes.apply(.rename(id: "not-a-thought", to: "Anything"), to: &memory, pins: &pins) == false)

        #expect(memory == before)
        #expect(pins.isEmpty)
    }

    // MARK: - Merge

    @Test func mergeMovesEverythingAcrossAndRemovesTheFoldedThought() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.merge(from: "the-pricing-page", into: "saying-yes-under-pressure"), to: &memory, pins: &pins))

        #expect(memory.thoughts["the-pricing-page"] == nil)
        let kept = try #require(memory.thoughts["saying-yes-under-pressure"])
        #expect(kept.label == "Saying yes under pressure")
        #expect(kept.aliases.contains("The pricing page"))
        #expect(kept.evidence.map(\.quote).contains("I think I already know I don't want the pricing page."))
        #expect(kept.timeline.map(\.note).contains("Leaning towards saying no."))
        // The folded thought's link to Meera now starts from the thought it joined.
        #expect(kept.links.contains { $0.target == "meera" && $0.reason == "asked for by" })
        #expect(pins.merges == [Pins.Merge(from: "the-pricing-page", into: "saying-yes-under-pressure", names: ["The pricing page"], intoLabel: "Saying yes under pressure")])
        #expect(pins.resolve("the-pricing-page") == "saying-yes-under-pressure")
    }

    @Test func linksThatPointedAtTheFoldedThoughtFollowIt() throws {
        var memory = try week()
        var pins = Pins()

        // "Trouble sleeping" links to "Saying yes under pressure". Fold that into Meera.
        MemoryFixes.apply(.merge(from: "saying-yes-under-pressure", into: "meera"), to: &memory, pins: &pins)

        #expect(memory.thoughts["trouble-sleeping"]?.links.map(\.target) == ["meera"])
        // A link between the two thoughts themselves would point at itself, so it is dropped.
        #expect(memory.thoughts["meera"]?.links.contains { $0.target == "meera" } == false)
    }

    @Test func aMergeThatMakesNoSenseChangesNothing() throws {
        var memory = try week()
        var pins = Pins()
        let before = memory

        #expect(MemoryFixes.apply(.merge(from: "meera", into: "meera"), to: &memory, pins: &pins) == false)
        #expect(MemoryFixes.apply(.merge(from: "meera", into: "nobody"), to: &memory, pins: &pins) == false)

        #expect(memory == before)
        #expect(pins.isEmpty)
    }

    // MARK: - Delete

    @Test func deleteRemovesTheThoughtItsLinksAndRecordsItsNames() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.delete(id: "meera"), to: &memory, pins: &pins))

        #expect(memory.thoughts["meera"] == nil)
        #expect(memory.thoughts["saying-yes-under-pressure"]?.links.isEmpty == true)
        #expect(memory.thoughts["the-pricing-page"]?.links.isEmpty == true)
        #expect(pins.deletions == [Pins.Deletion(id: "meera", label: "Meera", names: [])])
        #expect(pins.hasDeleted(name: "MEERA"))
    }

    // MARK: - Links

    @Test func aLinkMadeByHandIsKeptApartFromTheAIsLinks() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.addLink(from: "running", to: "trouble-sleeping", reason: " helps with "), to: &memory, pins: &pins))

        #expect(memory.thoughts["running"]?.userLinks == [UserLink(target: "trouble-sleeping", reason: "helps with")])
        #expect(memory.thoughts["running"]?.links.isEmpty == true)
        #expect(pins.linksAdded == [Pins.LinkPin(from: "running", to: "trouble-sleeping", reason: "helps with")])

        // Linking the same two again replaces the reason instead of adding a second link.
        MemoryFixes.apply(.addLink(from: "trouble-sleeping", to: "running", reason: "eased by"), to: &memory, pins: &pins)
        #expect(pins.linksAdded.count == 1)
        #expect(memory.thoughts["trouble-sleeping"]?.userLinks == [UserLink(target: "running", reason: "eased by")])
        #expect(memory.thoughts["running"]?.userLinks.isEmpty == true)
    }

    @Test func aLinkNeedsTwoDifferentThoughtsAndAReason() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.addLink(from: "running", to: "running", reason: "is"), to: &memory, pins: &pins) == false)
        #expect(MemoryFixes.apply(.addLink(from: "running", to: "nobody", reason: "is"), to: &memory, pins: &pins) == false)
        #expect(MemoryFixes.apply(.addLink(from: "running", to: "arjun", reason: "  "), to: &memory, pins: &pins) == false)
        #expect(pins.isEmpty)
    }

    @Test func removingAnAILinkTakesItOutAndForbidsItsReturn() throws {
        var memory = try week()
        var pins = Pins()

        #expect(MemoryFixes.apply(.removeLink("meera", "the-pricing-page"), to: &memory, pins: &pins))

        #expect(memory.thoughts["the-pricing-page"]?.links.isEmpty == true)
        #expect(pins.isLinkRemoved("the-pricing-page", "meera"))
        // The other links are untouched.
        #expect(memory.thoughts["saying-yes-under-pressure"]?.links.map(\.target) == ["meera"])
    }

    @Test func removingALinkMadeByHandJustTakesItAway() throws {
        var memory = try week()
        var pins = Pins()
        MemoryFixes.apply(.addLink(from: "running", to: "arjun", reason: "talked about with"), to: &memory, pins: &pins)

        #expect(MemoryFixes.apply(.removeLink("arjun", "running"), to: &memory, pins: &pins))

        #expect(memory.thoughts["running"]?.userLinks.isEmpty == true)
        #expect(pins.isEmpty)
        // There was never a link between these two.
        #expect(MemoryFixes.apply(.removeLink("arjun", "meera"), to: &memory, pins: &pins) == false)
    }

    @Test func addingALinkBackUndoesAnEarlierRemoval() throws {
        var memory = try week()
        var pins = Pins()
        MemoryFixes.apply(.removeLink("meera", "the-pricing-page"), to: &memory, pins: &pins)

        MemoryFixes.apply(.addLink(from: "the-pricing-page", to: "meera", reason: "asked for by"), to: &memory, pins: &pins)

        #expect(pins.linksRemoved.isEmpty)
        #expect(memory.thoughts["the-pricing-page"]?.userLinks.map(\.target) == ["meera"])
    }

    // MARK: - On disk

    @Test func theFixesFileAndTheNotesReadBackTheSame() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = MemoryStore(root: root)

        var memory = try week()
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "trouble-sleeping", to: "Bad nights"), to: &memory, pins: &pins)
        MemoryFixes.apply(.merge(from: "arjun", into: "running"), to: &memory, pins: &pins)
        MemoryFixes.apply(.delete(id: "the-launch"), to: &memory, pins: &pins)
        MemoryFixes.apply(.addLink(from: "running", to: "trouble-sleeping", reason: "helps with"), to: &memory, pins: &pins)
        MemoryFixes.apply(.removeLink("meera", "the-pricing-page"), to: &memory, pins: &pins)

        try store.write(memory, replacing: MemorySnapshot())
        try store.savePins(pins)

        #expect(store.loadPins() == pins)
        // Notes keep their lines in date order, so compare with memory put through the same writing and reading.
        let asWritten = memory.thoughts.compactMapValues { ThoughtNote.parse(ThoughtNote.render($0), id: $0.id) }
        #expect(store.loadSnapshot().thoughts == asWritten)
        #expect(asWritten.count == memory.thoughts.count)

        let json = try String(contentsOf: store.pinsURL, encoding: .utf8)
        for key in ["\"renames\"", "\"merges\"", "\"deletions\"", "\"links_added\"", "\"links_removed\"", "\"into_label\"", "\"names\""] {
            #expect(json.contains(key), "missing \(key)")
        }
        let note = try String(contentsOf: store.thoughtURL("running"), encoding: .utf8)
        #expect(note.contains("## Linked by you\n\n- [[trouble-sleeping]] · helps with"))

        // With no fixes left, the file is removed.
        try store.savePins(Pins())
        #expect(!FileManager.default.fileExists(atPath: store.pinsURL.path))
    }

    @Test func makingMemoryAgreeWithTheFixesTwiceChangesNothingMore() throws {
        var memory = try week()
        var pins = Pins()
        MemoryFixes.apply(.rename(id: "meera", to: "Meera R"), to: &memory, pins: &pins)
        MemoryFixes.apply(.addLink(from: "running", to: "meera", reason: "talked through with"), to: &memory, pins: &pins)
        let once = memory

        MemoryFixes.enforce(pins, on: &memory)

        #expect(memory == once)
    }
}

/// The promise of M6: every fix survives a full rebuild.
@Suite struct FixesSurviveARebuildTests {

    /// A sandbox with the made-up week digested once, ready for fixes and a rebuild.
    private func digestedWeek(rebuildReplies: [String] = MemoryWeek.replies) async -> (sandbox: MemorySandbox, engine: MemoryEngine, provider: FakeProvider) {
        let sandbox = MemorySandbox()
        for entry in MemoryWeek.entries {
            sandbox.writeEntry(entry)
        }
        let provider = FakeProvider((MemoryWeek.replies + rebuildReplies).map { .reply([$0]) })
        let engine = sandbox.engine(provider)
        await engine.runPass()
        return (sandbox, engine, provider)
    }

    @Test func aRenameSurvives() async {
        let (sandbox, engine, _) = await digestedWeek()
        #expect(await engine.fix(.rename(id: "trouble-sleeping", to: "Bad nights")))

        await engine.rebuild()

        let thought = sandbox.store.loadSnapshot().thoughts["trouble-sleeping"]
        #expect(thought?.label == "Bad nights")
        #expect(thought?.evidence.count == 3)
    }

    @Test func aRenameSurvivesEvenWhenTheAINamesTheThoughtDifferentlyTheSecondTime() async throws {
        // On the rebuild, Monday's reply calls it "Sleepless nights" and mentions the old name only as another name.
        let mondayAgain = MemoryWeek.mondayReply
            .replacingOccurrences(of: "\"label\":\"Trouble sleeping\"", with: "\"label\":\"Sleepless nights\"")
            .replacingOccurrences(of: "\"aliases\":[],\"kind\":\"feeling\"", with: "\"aliases\":[\"Trouble sleeping\"],\"kind\":\"feeling\"")
            .replacingOccurrences(of: "\"from\":\"Trouble sleeping\"", with: "\"from\":\"Sleepless nights\"")
        #expect(mondayAgain != MemoryWeek.mondayReply)
        let replies = [mondayAgain] + Array(MemoryWeek.replies.dropFirst())

        let (sandbox, engine, _) = await digestedWeek(rebuildReplies: replies)
        await engine.fix(.rename(id: "trouble-sleeping", to: "Bad nights"))

        await engine.rebuild()

        let memory = sandbox.store.loadSnapshot()
        #expect(memory.thoughts["sleepless-nights"] == nil)
        let thought = try #require(memory.thoughts["trouble-sleeping"])
        #expect(thought.label == "Bad nights")
        #expect(thought.aliases.contains("Sleepless nights"))
        #expect(thought.evidence.count == 3)
    }

    @Test func aMergeSurvives() async throws {
        let (sandbox, engine, _) = await digestedWeek()
        #expect(await engine.fix(.merge(from: "the-pricing-page", into: "saying-yes-under-pressure")))

        await engine.rebuild()

        let memory = sandbox.store.loadSnapshot()
        #expect(memory.thoughts["the-pricing-page"] == nil)
        let kept = try #require(memory.thoughts["saying-yes-under-pressure"])
        #expect(kept.evidence.map(\.quote).contains("I think I already know I don't want the pricing page."))
        #expect(kept.evidence.map(\.quote).contains("I said I needed to think about it."))
        #expect(!sandbox.thoughtFileExists("the-pricing-page"))
    }

    @Test func aDeletionSurvives() async {
        let (sandbox, engine, _) = await digestedWeek()
        #expect(await engine.fix(.delete(id: "arjun")))
        #expect(!sandbox.thoughtFileExists("arjun"))

        await engine.rebuild()

        #expect(sandbox.store.loadSnapshot().thoughts["arjun"] == nil)
        #expect(!sandbox.thoughtFileExists("arjun"))
        let wednesday = sandbox.store.loadDigest(entryID: MemoryWeek.wednesday.id)
        #expect(wednesday?.rejected.contains(EntryDigest.Rejection(item: "new_thought", reason: "You deleted this thought.")) == true)
    }

    @Test func aLinkMadeByHandSurvives() async {
        let (sandbox, engine, _) = await digestedWeek()
        #expect(await engine.fix(.addLink(from: "running", to: "trouble-sleeping", reason: "helps with")))

        await engine.rebuild()

        let memory = sandbox.store.loadSnapshot()
        #expect(memory.thoughts["running"]?.userLinks == [UserLink(target: "trouble-sleeping", reason: "helps with")])
        let graph = GraphBuilder.build(from: memory, saved: [:]).graph
        #expect(graph.edges.contains { $0.id == "running|trouble-sleeping" && $0.reasons == ["helps with"] })
    }

    @Test func aRemovedLinkStaysRemoved() async {
        let (sandbox, engine, _) = await digestedWeek()
        #expect(await engine.fix(.removeLink("meera", "the-pricing-page")))

        await engine.rebuild()

        #expect(sandbox.store.loadSnapshot().thoughts["the-pricing-page"]?.links.isEmpty == true)
        let friday = sandbox.store.loadDigest(entryID: MemoryWeek.friday.id)
        #expect(friday?.rejected.contains(EntryDigest.Rejection(item: "link", reason: "You removed this link.")) == true)
    }

    @Test func theFixesFileItselfIsKeptByARebuild() async {
        let (sandbox, engine, _) = await digestedWeek()
        await engine.fix(.rename(id: "meera", to: "Meera R"))
        let before = sandbox.store.loadPins()

        await engine.rebuild()

        #expect(sandbox.store.loadPins() == before)
        #expect(!before.isEmpty)
    }

    @Test func aFixWorksWithMemorySwitchedOffAndSendsNothing() async {
        let (sandbox, engine, provider) = await digestedWeek()
        let sentBefore = provider.requests.count
        sandbox.enabled = false

        #expect(await engine.fix(.rename(id: "meera", to: "Meera R")))

        #expect(sandbox.store.loadSnapshot().thoughts["meera"]?.label == "Meera R")
        #expect(provider.requests.count == sentBefore)
    }

    @Test func aFixMadeWhileAnEntryIsBeingReadIsNotOverwritten() async {
        let sandbox = MemorySandbox()
        sandbox.writeEntry(MemoryWeek.monday)
        sandbox.writeEntry(MemoryWeek.wednesday)
        let provider = FakeProvider([.reply([MemoryWeek.mondayReply]), .reply([MemoryWeek.wednesdayReply])])
        let store = sandbox.store

        // While Wednesday's entry is with the AI, the user deletes "Meera" on the map.
        provider.onRequest = { earlier in
            guard earlier == 1 else { return }
            let before = store.loadSnapshot()
            var memory = before
            var pins = store.loadPins()
            MemoryFixes.apply(.delete(id: "meera"), to: &memory, pins: &pins)
            try? store.savePins(pins)
            try? store.write(memory, replacing: before)
        }

        #expect(await sandbox.engine(provider).runPass() == .finished(digested: 2))

        let memory = store.loadSnapshot()
        #expect(memory.thoughts["meera"] == nil)
        #expect(!sandbox.thoughtFileExists("meera"))
        #expect(store.loadPins().isDeleted("meera"))
        // Wednesday's own thoughts still went in.
        #expect(memory.thoughts["running"] != nil)
    }
}
