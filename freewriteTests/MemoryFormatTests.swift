//
//  MemoryFormatTests.swift
//  freewriteTests
//
//  Checks the building blocks of memory: finding quotes in an entry, reading
//  the AI's reply strictly, and the files in the memory folder.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct QuoteMatcherTests {

    private let entry = """
    Couldn’t sleep again. I keep replaying the call with Meera about the launch.

    I said “yes” to everything she asked — and then
    felt sick about it for the rest of the day.
    """

    @Test func findsAnExactQuote() {
        #expect(QuoteMatcher.locate("I keep replaying the call with Meera", in: entry) == "I keep replaying the call with Meera")
    }

    @Test func forgivesSpacingAndLineBreaks() {
        let found = QuoteMatcher.locate("she asked — and then   felt sick about it", in: entry)

        // What comes back is the entry's own text, line break included.
        #expect(found == "she asked — and then\nfelt sick about it")
    }

    @Test func forgivesQuoteMarkAndDashStyleButKeepsTheEntrysOwn() {
        #expect(QuoteMatcher.locate("Couldn't sleep again.", in: entry) == "Couldn’t sleep again.")
        #expect(QuoteMatcher.locate("I said \"yes\" to everything she asked - and then", in: entry) == "I said “yes” to everything she asked — and then")
    }

    @Test func acceptsAQuoteTheModelWrappedInQuoteMarks() {
        #expect(QuoteMatcher.locate("\"I keep replaying the call with Meera\"", in: entry) == "I keep replaying the call with Meera")
    }

    @Test func rejectsAChangedWord() {
        #expect(QuoteMatcher.locate("I keep replaying the meeting with Meera", in: entry) == nil)
    }

    @Test func rejectsAParaphraseAndAnInvention() {
        #expect(QuoteMatcher.locate("I agreed to all her requests and regretted it", in: entry) == nil)
        #expect(QuoteMatcher.locate("I am terrified of failing at this.", in: entry) == nil)
    }

    @Test func rejectsEllipsesAndStitchedPassages() {
        #expect(QuoteMatcher.locate("Couldn't sleep again... felt sick about it", in: entry) == nil)
        #expect(QuoteMatcher.locate("Couldn't sleep again. I said yes to everything", in: entry) == nil)
    }

    @Test func isCaseSensitive() {
        #expect(QuoteMatcher.locate("i keep replaying the call with meera", in: entry) == nil)
    }

    @Test func rejectsQuotesTooShortToMeanAnything() {
        #expect(QuoteMatcher.locate("I", in: entry) == nil)
        #expect(QuoteMatcher.locate("the", in: entry) == nil)
        #expect(QuoteMatcher.locate("", in: entry) == nil)
    }

    @Test func anEmptyEntryMatchesNothing() {
        #expect(QuoteMatcher.locate("anything at all", in: "  \n ") == nil)
    }
}

@Suite struct DigestParserTests {

    @Test func readsAFullReply() throws {
        let result = try DigestParser.parse(MemoryWeek.fridayReply)

        #expect(result.summary.hasPrefix("Meera asked for more"))
        #expect(result.thoughtUpdates.map(\.thoughtID) == ["meera", "trouble-sleeping"])
        #expect(result.thoughtUpdates[0].newSummary == nil)
        #expect(result.newThoughts.map(\.label) == ["Saying yes", "The pricing page"])
        #expect(result.newThoughts[1].kind == .decision)
        #expect(result.newThoughts[0].aliases == ["Saying yes under pressure"])
        #expect(result.links.count == 1)
        #expect(result.links[0].reason == "asked for by")
        #expect(result.timelineNotes.count == 2)
        #expect(result.openLoops.isEmpty)
        #expect(result.profile == nil)
    }

    @Test func readsAnEmptyButValidReply() throws {
        let result = try DigestParser.parse(DigestJSON.reply(summary: "Nothing much."))

        #expect(result == DigestResult(summary: "Nothing much."))
    }

    @Test func acceptsJSONInsideACodeFence() throws {
        let fenced = "```json\n" + DigestJSON.reply(summary: "Fenced.") + "\n```"

        #expect(try DigestParser.parse(fenced).summary == "Fenced.")
    }

    @Test func acceptsAKindInAnyCapitalisation() throws {
        let reply = DigestJSON.reply(new: [DigestJSON.new("Meera", kind: "Person", summary: "A colleague.", quote: "a quote")])

        #expect(try DigestParser.parse(reply).newThoughts.first?.kind == .person)
    }

    @Test(arguments: [
        "not json at all",
        "",
        "[]",
        "Here is the JSON you asked for: {\"summary\": \"x\"}",
        "{\"summary\": \"only one field\"}",
    ])
    func refusesAnythingThatIsNotTheExpectedObject(reply: String) {
        #expect(throws: DigestParseError.self) {
            _ = try DigestParser.parse(reply)
        }
    }

    @Test func refusesAnExtraField() {
        let reply = DigestJSON.reply().replacingOccurrences(of: "{\"links\"", with: "{\"mood\":\"low\",\"links\"")

        #expect(throws: DigestParseError.self) {
            _ = try DigestParser.parse(reply)
        }
    }

    @Test func refusesAnItemWithAMissingOrExtraField() {
        let missing = DigestJSON.reply(links: [["from": "a", "to": "b", "reason": "because"]])
        let extra = DigestJSON.reply(notes: [["thought": "a", "note": "n", "quote": "q", "confidence": "high"]])

        #expect(throws: DigestParseError.self) { _ = try DigestParser.parse(missing) }
        #expect(throws: DigestParseError.self) { _ = try DigestParser.parse(extra) }
    }

    @Test func refusesTheWrongTypeOfValue() {
        let numberForText = DigestJSON.reply(updates: [["thought_id": 7, "quote": "q", "new_summary": NSNull(), "new_alias": NSNull()]])
        let textForList = DigestJSON.reply().replacingOccurrences(of: "\"open_loops\":[]", with: "\"open_loops\":\"none\"")

        #expect(throws: DigestParseError.self) { _ = try DigestParser.parse(numberForText) }
        #expect(throws: DigestParseError.self) { _ = try DigestParser.parse(textForList) }
    }

    @Test func refusesAKindThatIsNotOneOfTheSeven() {
        let reply = DigestJSON.reply(new: [DigestJSON.new("Mood", kind: "diagnosis", summary: "s", quote: "q")])

        #expect(throws: DigestParseError.self) { _ = try DigestParser.parse(reply) }
    }

    @Test func errorsNeverCarryTheRepliesText() {
        do {
            _ = try DigestParser.parse("a private sentence that is not JSON")
            Issue.record("Expected the reply to be refused.")
        } catch let error as DigestParseError {
            #expect(!error.reason.contains("private sentence"))
        } catch {
            Issue.record("Unexpected error type.")
        }
    }

    // MARK: - The schema sent to Claude must describe the same shape

    @Test func theSchemaMatchesWhatTheParserExpects() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: DigestSchema.data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])

        #expect(Set(properties.keys) == ["summary", "thought_updates", "new_thoughts", "links", "timeline_notes", "open_loops", "profile"])

        let kinds = try #require((((properties["new_thoughts"] as? [String: Any])?["items"] as? [String: Any])?["properties"] as? [String: Any])?["kind"] as? [String: Any])
        #expect(Set(kinds["enum"] as? [String] ?? []) == Set(ThoughtKind.allCases.map(\.rawValue)))
    }

    @Test func everyObjectInTheSchemaListsAllItsFieldsAndAllowsNoOthers() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: DigestSchema.data) as? [String: Any])
        var objectsChecked = 0

        func check(_ node: Any) {
            guard let dictionary = node as? [String: Any] else { return }
            if dictionary["type"] as? String == "object" {
                let properties = dictionary["properties"] as? [String: Any] ?? [:]
                #expect(dictionary["additionalProperties"] as? Bool == false)
                #expect(Set(dictionary["required"] as? [String] ?? []) == Set(properties.keys))
                objectsChecked += 1
            }
            for value in dictionary.values {
                check(value)
            }
        }
        check(schema)

        // The reply itself plus the four kinds of item.
        #expect(objectsChecked == 5)
    }
}

@Suite struct ThoughtNoteTests {

    private let entryA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let entryB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func sample() -> Thought {
        Thought(
            id: "saying-yes-under-pressure",
            label: "Saying yes: under \"pressure\"",
            kind: .theme,
            aliases: ["can't say no", "people-pleasing · at work"],
            summary: "Agreeing in the moment and feeling sick about it afterwards.",
            timeline: [
                TimelineNote(entryID: entryB, date: "2026-11-06", note: "Held back from agreeing · for the first time.", quote: "First time I haven't just said yes."),
            ],
            evidence: [
                Evidence(entryID: entryA, date: "2026-11-02", quote: "I said “yes” to everything she asked — and then\nfelt sick about it"),
                Evidence(entryID: entryB, date: "2026-11-06", quote: "First time I haven't just said yes."),
            ],
            links: [
                ThoughtLink(target: "meera", reason: "shows up around", entryID: entryA, date: "2026-11-02", quote: "I said yes to everything she asked"),
            ]
        )
    }

    @Test func aNoteReadsBackExactly() {
        let note = ThoughtNote.render(sample())

        #expect(ThoughtNote.parse(note, id: "saying-yes-under-pressure") == sample())
    }

    @Test func theNoteIsReadableAndLinksWorkInObsidian() {
        let note = ThoughtNote.render(sample())

        #expect(note.hasPrefix("---\n"))
        #expect(note.contains("kind: theme"))
        #expect(note.contains("aliases:\n  - \"can't say no\""))
        #expect(note.contains("first_seen: 2026-11-02"))
        #expect(note.contains("last_seen: 2026-11-06"))
        #expect(note.contains("## Timeline"))
        #expect(note.contains("## Evidence"))
        #expect(note.contains("## Links"))
        #expect(note.contains("- [[meera]] · 2026-11-02 · [00000000-0000-0000-0000-00000000000A] · shows up around"))
        // A quote that runs over two lines stays a two-line quote.
        #expect(note.contains("  > I said “yes” to everything she asked — and then\n  > felt sick about it"))
    }

    @Test func aThoughtWithNothingButANameStillWritesAValidNote() {
        let bare = Thought(id: "arjun", label: "Arjun", kind: .person)
        let note = ThoughtNote.render(bare)

        #expect(note.contains("aliases: []"))
        #expect(ThoughtNote.parse(note, id: "arjun") == bare)
    }

    @Test func aHandEditedNoteIsReadAsFarAsItMakesSense() throws {
        let edited = """
        ---
        label: Meera
        kind: Person
        my_own_field: something I added
        ---

        # Meera

        A colleague leading the launch.
        I added this second line by hand.

        ## Evidence

        - 2026-11-02 · [00000000-0000-0000-0000-00000000000A]
          > I keep replaying the call with Meera
        - this line is not in the right shape
          > so its quote is ignored
        - 2026-11-06 · [not-a-real-id]
          > and so is this one

        ## My own section

        - anything here is left alone
        """

        let thought = try #require(ThoughtNote.parse(edited, id: "meera"))

        #expect(thought.label == "Meera")
        #expect(thought.kind == .person)
        #expect(thought.summary == "A colleague leading the launch. I added this second line by hand.")
        #expect(thought.evidence.map(\.quote) == ["I keep replaying the call with Meera"])
    }

    @Test func somethingThatIsNotAThoughtNoteIsNotRead() {
        #expect(ThoughtNote.parse("Just some notes I keep in this folder.", id: "notes") == nil)
        #expect(ThoughtNote.parse("---\nkind: theme\n---\n\nNo name anywhere.", id: "nameless") == nil)
        #expect(ThoughtNote.parse("", id: "empty") == nil)
    }
}

@Suite struct MemoryStoreTests {

    /// A memory store in a folder that exists only for one test.
    private final class Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Freewrite", isDirectory: true)

        var store: MemoryStore { MemoryStore(root: root) }

        deinit {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    private let entryID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

    private func memory() -> MemorySnapshot {
        var snapshot = MemorySnapshot()
        snapshot.thoughts["meera"] = Thought(
            id: "meera",
            label: "Meera",
            kind: .person,
            summary: "A colleague leading the launch.",
            evidence: [Evidence(entryID: entryID, date: "2026-11-02", quote: "I keep replaying the call with Meera")]
        )
        snapshot.thoughts["the-launch"] = Thought(
            id: "the-launch",
            label: "The launch",
            kind: .event,
            evidence: [Evidence(entryID: entryID, date: "2026-11-02", quote: "the call with Meera about the launch")]
        )
        snapshot.profile = "They are in the middle of a launch."
        return snapshot
    }

    private func digest() -> EntryDigest {
        EntryDigest(
            entryID: entryID,
            entryDate: "2026-11-02",
            textHash: "abc123",
            digestedAt: Date(timeIntervalSince1970: 1_794_000_000),
            model: "model-for-memory",
            summary: "A sleepless night.",
            thoughts: ["meera", "the-launch"],
            openLoops: ["Reply to Meera"],
            rejected: [EntryDigest.Rejection(item: "new_thought", reason: "Its quote is not in the entry.")],
            inputTokens: 1200,
            outputTokens: 300,
            failed: false,
            failureReason: nil
        )
    }

    @Test func theFolderIsLaidOutAsThePRDDescribes() throws {
        let sandbox = Sandbox()
        try sandbox.store.write(memory(), replacing: MemorySnapshot())
        try sandbox.store.saveDigest(digest())

        let base = sandbox.root.appendingPathComponent("memory")
        for path in ["profile.md", "thoughts/meera.md", "thoughts/the-launch.md", "entries/00000000-0000-0000-0000-00000000000A.json"] {
            #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent(path).path), "missing \(path)")
        }
    }

    @Test func whatIsSavedReadsBackTheSame() throws {
        let sandbox = Sandbox()
        try sandbox.store.write(memory(), replacing: MemorySnapshot())
        try sandbox.store.saveDigest(digest())

        #expect(sandbox.store.loadSnapshot() == memory())
        #expect(sandbox.store.loadDigest(entryID: entryID) == digest())
        #expect(sandbox.store.loadAllDigests() == [digest()])
    }

    @Test func theFilesArePlainAndReadable() throws {
        let sandbox = Sandbox()
        try sandbox.store.write(memory(), replacing: MemorySnapshot())
        try sandbox.store.saveDigest(digest())

        let profile = try String(contentsOf: sandbox.store.profileURL, encoding: .utf8)
        #expect(profile == "# Profile\n\nThey are in the middle of a launch.\n")

        let json = try String(contentsOf: sandbox.store.digestURL(entryID), encoding: .utf8)
        for key in ["\"entry_id\"", "\"entry_date\"", "\"text_hash\"", "\"digested_at\"", "\"open_loops\"", "\"input_tokens\"", "\"summary\"", "\"thoughts\""] {
            #expect(json.contains(key), "missing \(key)")
        }
    }

    @Test func onlyWhatChangedIsRewrittenAndRemovedThoughtsLoseTheirFile() throws {
        let sandbox = Sandbox()
        let first = memory()
        try sandbox.store.write(first, replacing: MemorySnapshot())

        var second = first
        second.thoughts["the-launch"] = nil
        second.thoughts["meera"]?.summary = "A colleague whose requests are hard to refuse."
        try sandbox.store.write(second, replacing: first)

        #expect(!FileManager.default.fileExists(atPath: sandbox.store.thoughtURL("the-launch").path))
        #expect(sandbox.store.loadSnapshot() == second)
    }

    @Test func aNoteThatCannotBeReadIsSkippedAndNeverTouched() throws {
        let sandbox = Sandbox()
        try sandbox.store.write(memory(), replacing: MemorySnapshot())
        let broken = sandbox.store.thoughtURL("my-own-note")
        try "Something I wrote by hand. Not a thought note.".write(to: broken, atomically: true, encoding: .utf8)

        let loaded = sandbox.store.loadSnapshot()
        #expect(loaded.unreadableIDs == ["my-own-note"])
        #expect(loaded.thoughts.count == 2)

        // A rebuild clears what the AI built and leaves the hand-written file alone.
        sandbox.store.forgetAIBuilt()
        #expect(FileManager.default.fileExists(atPath: broken.path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.store.thoughtURL("meera").path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.store.profileURL.path))
    }

    @Test func pinsAreReadAndAMissingOrPartialFileMeansNoFixes() throws {
        let sandbox = Sandbox()
        #expect(sandbox.store.loadPins() == Pins())

        sandbox.store.ensureFolder()
        let partial = """
        {
          "merges": [{"from": "saying-yes", "into": "saying-yes-under-pressure"}],
          "deletions": [{"id": "fear-of-failing", "label": "Fear of failing"}],
          "links_removed": [{"from": "running", "to": "meera"}]
        }
        """
        try partial.write(to: sandbox.store.pinsURL, atomically: true, encoding: .utf8)

        let pins = sandbox.store.loadPins()
        #expect(pins.resolve("saying-yes") == "saying-yes-under-pressure")
        #expect(pins.isDeleted("fear-of-failing"))
        #expect(pins.hasDeleted(name: "fear of FAILING"))
        #expect(pins.isLinkRemoved("meera", "running"))
        #expect(pins.renames.isEmpty)
    }

    @Test func forgettingEverythingRemovesTheFolderAndNothingElse() throws {
        let sandbox = Sandbox()
        let entry = sandbox.root.appendingPathComponent("[\(entryID.uuidString)]-[2026-11-02-23-00-00].md")
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try "My entry.".write(to: entry, atomically: true, encoding: .utf8)
        try sandbox.store.write(memory(), replacing: MemorySnapshot())

        sandbox.store.forgetEverything()

        #expect(!FileManager.default.fileExists(atPath: sandbox.store.folder.path))
        #expect(FileManager.default.fileExists(atPath: entry.path))
    }

    @Test func namesBecomeSafeFileNames() {
        #expect(MemoryText.slug("Saying yes, under pressure!") == "saying-yes-under-pressure")
        #expect(MemoryText.slug("  Café / résumé  ") == "cafe-resume")
        #expect(MemoryText.slug("../../etc/passwd") == "etc-passwd")
        #expect(MemoryText.slug("???") == "thought")
        #expect(MemoryText.normalizedName("  Can't SAY   no! ") == "cant say no")
        #expect(MemoryText.normalizedName("Can’t say no") == MemoryText.normalizedName("cant say no"))
    }
}
