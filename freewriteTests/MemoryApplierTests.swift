//
//  MemoryApplierTests.swift
//  freewriteTests
//
//  Checks the step that decides what from an AI digest is allowed into memory:
//  no invented quotes, the user's fixes win, reuse before create, and applying
//  the same entry twice changes nothing. Uses the made-up week of entries.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct MemoryApplierTests {

    private let monday = MemoryWeek.digested(MemoryWeek.monday)
    private let wednesday = MemoryWeek.digested(MemoryWeek.wednesday)
    private let friday = MemoryWeek.digested(MemoryWeek.friday)

    /// Memory after Monday's entry has been digested.
    private func afterMonday(pins: Pins = Pins()) throws -> (memory: MemorySnapshot, outcome: MemoryApplier.Outcome) {
        var memory = MemorySnapshot()
        let outcome = MemoryApplier.apply(try DigestParser.parse(MemoryWeek.mondayReply), for: monday, to: &memory, pins: pins)
        return (memory, outcome)
    }

    private func apply(_ reply: String, for entry: DigestedEntry, to memory: inout MemorySnapshot, pins: Pins = Pins()) throws -> MemoryApplier.Outcome {
        MemoryApplier.apply(try DigestParser.parse(reply), for: entry, to: &memory, pins: pins)
    }

    // MARK: - Evidence

    @Test func newThoughtsAreCreatedWithTheEntrysOwnWords() throws {
        let (memory, outcome) = try afterMonday()

        #expect(Set(memory.thoughts.keys) == ["saying-yes-under-pressure", "meera", "trouble-sleeping", "the-launch"])
        #expect(outcome.touched == ["meera", "saying-yes-under-pressure", "the-launch", "trouble-sleeping"])

        let sleep = try #require(memory.thoughts["trouble-sleeping"])
        #expect(sleep.kind == .feeling)
        // The reply quoted it with a straight apostrophe; the entry's curly one is what is kept.
        #expect(sleep.evidence == [Evidence(entryID: MemoryWeek.monday.id, date: "2026-11-02", quote: "Couldn’t sleep again.")])
        #expect(memory.thoughts["saying-yes-under-pressure"]?.aliases == ["can't say no"])
        #expect(memory.profile.hasPrefix("They are in the middle of a launch"))
    }

    @Test func aQuoteThatIsNotInTheEntryIsRefused() throws {
        let (memory, outcome) = try afterMonday()

        #expect(memory.thoughts["fear-of-failing"] == nil)
        #expect(outcome.rejected == [EntryDigest.Rejection(item: "new_thought", reason: "Its quote is not in the entry.")])
    }

    @Test func everyThoughtAndLinkCarriesAQuoteFoundInItsEntry() throws {
        var memory = MemorySnapshot()
        for (entry, reply) in zip(MemoryWeek.entries, MemoryWeek.replies) {
            _ = try apply(reply, for: MemoryWeek.digested(entry), to: &memory)
        }
        let texts = Dictionary(uniqueKeysWithValues: MemoryWeek.entries.map { ($0.id, $0.text) })

        for thought in memory.thoughts.values {
            #expect(!thought.evidence.isEmpty, "\(thought.id) has no evidence")
            for item in thought.evidence {
                #expect(texts[item.entryID]?.contains(item.quote) == true, "\(thought.id): evidence not in its entry")
            }
            for note in thought.timeline {
                #expect(texts[note.entryID]?.contains(note.quote) == true, "\(thought.id): timeline quote not in its entry")
            }
            for link in thought.links {
                #expect(texts[link.entryID]?.contains(link.quote) == true, "\(thought.id): link quote not in its entry")
                #expect(memory.thoughts[link.target] != nil, "\(thought.id): link points nowhere")
            }
        }
    }

    // MARK: - Reuse before create

    @Test func aNewThoughtThatGoesByAKnownNameJoinsTheExistingOne() throws {
        var memory = try afterMonday().memory
        _ = try apply(MemoryWeek.fridayReply, for: friday, to: &memory)

        // "Saying yes" came with the other name "Saying yes under pressure", which memory already has.
        #expect(memory.thoughts["saying-yes"] == nil)
        let existing = try #require(memory.thoughts["saying-yes-under-pressure"])
        #expect(existing.label == "Saying yes under pressure")
        #expect(existing.aliases == ["can't say no", "Saying yes"])
        #expect(existing.evidence.map(\.quote).contains("First time I haven't just said yes."))
        #expect(existing.timeline.map(\.note) == ["Held back from agreeing for the first time."])
    }

    @Test func theSameNameInDifferentCapitalsOrPunctuationIsTheSameThought() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(new: [
            DigestJSON.new("MEERA!", kind: "person", summary: "Her again.", quote: "Meera asked if I could also take the pricing page."),
            DigestJSON.new("Cant say no", kind: "theme", summary: "Same thing.", quote: "First time I haven't just said yes."),
        ])
        let outcome = try apply(reply, for: friday, to: &memory)

        #expect(memory.thoughts.count == 4)
        #expect(outcome.touched == ["meera", "saying-yes-under-pressure"])
        #expect(memory.thoughts["meera"]?.evidence.count == 2)
    }

    @Test func linksAndNotesCanPointAtAThoughtCreatedInTheSameReply() throws {
        var memory = try afterMonday().memory
        _ = try apply(MemoryWeek.fridayReply, for: friday, to: &memory)

        let pricing = try #require(memory.thoughts["the-pricing-page"])
        #expect(pricing.links.map(\.target) == ["meera"])
        #expect(pricing.links.first?.reason == "asked for by")
    }

    // MARK: - Updates, links and notes

    @Test func anUpdateAddsEvidenceAndCanReviseTheDescription() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(updates: [
            DigestJSON.update("the-launch", quote: "The launch date moved again.", newSummary: "A launch at work whose date keeps moving.", newAlias: "launch date"),
        ])
        _ = try apply(reply, for: wednesday, to: &memory)

        let launch = try #require(memory.thoughts["the-launch"])
        #expect(launch.evidence.count == 2)
        #expect(launch.summary == "A launch at work whose date keeps moving.")
        #expect(launch.aliases == ["launch date"])
        #expect(launch.firstSeen == "2026-11-02")
        #expect(launch.lastSeen == "2026-11-04")
    }

    @Test func itemsThatNameAnUnknownThoughtAreRefused() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(
            updates: [DigestJSON.update("made-up-id", quote: "The launch date moved again.")],
            links: [DigestJSON.link("the-launch", "nothing-like-this", reason: "led to", quote: "The launch date moved again.")],
            notes: [DigestJSON.note("also-made-up", "Something changed.", quote: "The launch date moved again.")]
        )
        let outcome = try apply(reply, for: wednesday, to: &memory)

        #expect(outcome.rejected.map(\.item) == ["thought_update", "timeline_note", "link"])
        #expect(outcome.rejected.allSatisfy { $0.reason == "It named a thought that is not in memory." })
        #expect(outcome.touched.isEmpty)
    }

    @Test func aLinkNeedsTwoDifferentThoughtsAReasonAndAQuote() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(links: [
            DigestJSON.link("meera", "Meera", reason: "is", quote: "The launch date moved again."),
            DigestJSON.link("meera", "the-launch", reason: "   ", quote: "The launch date moved again."),
            DigestJSON.link("meera", "the-launch", reason: "leads", quote: "She runs the whole launch herself."),
        ])
        let outcome = try apply(reply, for: wednesday, to: &memory)

        #expect(outcome.rejected.map(\.reason) == [
            "It linked a thought to itself.",
            "It gave no reason.",
            "Its quote is not in the entry.",
        ])
        #expect(memory.thoughts["meera"]?.links.isEmpty == true)
    }

    @Test func leavingTheProfileOutKeepsTheOldOne() throws {
        var memory = try afterMonday().memory
        let before = memory.profile
        _ = try apply(MemoryWeek.wednesdayReply, for: wednesday, to: &memory)

        #expect(memory.profile == before)
    }

    // MARK: - The user's fixes win

    @Test func aDeletedThoughtCannotComeBackOrBeAddedTo() throws {
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "meera", label: "Meera")]

        // Creating it again under the same name is refused, and so are links to it.
        let (memory, outcome) = try afterMonday(pins: pins)
        #expect(memory.thoughts["meera"] == nil)
        #expect(outcome.rejected.contains(EntryDigest.Rejection(item: "new_thought", reason: "You deleted this thought.")))
        #expect(memory.thoughts["saying-yes-under-pressure"]?.links.isEmpty == true)

        // Adding evidence to it by id is refused too.
        var later = memory
        let update = DigestJSON.reply(updates: [DigestJSON.update("meera", quote: "Meera asked if I could also take the pricing page.")])
        let second = try apply(update, for: friday, to: &later, pins: pins)
        #expect(second.rejected == [EntryDigest.Rejection(item: "thought_update", reason: "You deleted this thought.")])
        #expect(later.thoughts["meera"] == nil)
    }

    @Test func aThoughtDeletedInPinsIsRemovedEvenIfItsNoteIsStillThere() throws {
        var memory = try afterMonday().memory
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "the-launch", label: "The launch")]

        _ = try apply(DigestJSON.reply(), for: wednesday, to: &memory, pins: pins)

        #expect(memory.thoughts["the-launch"] == nil)
    }

    @Test func aMergedAwayThoughtSendsItsEvidenceToTheOneItJoined() throws {
        var memory = try afterMonday().memory
        var pins = Pins()
        pins.merges = [Pins.Merge(from: "agreeing-too-fast", into: "saying-yes-under-pressure")]

        let reply = DigestJSON.reply(
            updates: [DigestJSON.update("agreeing-too-fast", quote: "First time I haven't just said yes.")],
            new: [DigestJSON.new("Agreeing too fast", kind: "theme", summary: "Same pattern.", quote: "I said I needed to think about it.")]
        )
        let outcome = try apply(reply, for: friday, to: &memory, pins: pins)

        #expect(memory.thoughts["agreeing-too-fast"] == nil)
        #expect(outcome.rejected.isEmpty)
        #expect(outcome.touched == ["saying-yes-under-pressure"])
        #expect(memory.thoughts["saying-yes-under-pressure"]?.evidence.count == 3)
    }

    @Test func aRenameIsKept() throws {
        var pins = Pins()
        pins.renames = [Pins.Rename(id: "trouble-sleeping", label: "Bad nights")]

        let memory = try afterMonday(pins: pins).memory

        #expect(memory.thoughts["trouble-sleeping"]?.label == "Bad nights")
    }

    @Test func aLinkTheUserRemovedIsNotPutBack() throws {
        var pins = Pins()
        pins.linksRemoved = [Pins.LinkPin(from: "meera", to: "saying-yes-under-pressure", reason: nil)]

        let (memory, outcome) = try afterMonday(pins: pins)

        #expect(memory.thoughts["saying-yes-under-pressure"]?.links.isEmpty == true)
        #expect(outcome.rejected.contains(EntryDigest.Rejection(item: "link", reason: "You removed this link.")))
        // The other link in the same reply is unaffected.
        #expect(memory.thoughts["trouble-sleeping"]?.links.map(\.target) == ["saying-yes-under-pressure"])
    }

    // MARK: - Doing it twice changes nothing

    @Test func applyingTheSameDigestTwiceGivesTheSameMemory() throws {
        var memory = try afterMonday().memory
        let once = memory
        _ = try apply(MemoryWeek.mondayReply, for: monday, to: &memory)

        #expect(memory == once)
    }

    @Test func aChangedDigestForTheSameEntryReplacesItsOldLines() throws {
        var memory = try afterMonday().memory
        let revised = DigestJSON.reply(new: [
            DigestJSON.new("Meera", kind: "person", summary: "A colleague.", quote: "I keep replaying the call with Meera about the launch."),
        ])
        let outcome = try apply(revised, for: monday, to: &memory)

        // Only what the new digest supports is left: nothing lingers from the first one.
        #expect(Set(memory.thoughts.keys) == ["meera"])
        #expect(memory.thoughts["meera"]?.evidence.count == 1)
        #expect(outcome.touched == ["meera"])
    }

    @Test func removingAnEntryTakesOnlyItsLinesAndDropsThoughtsLeftWithNone() throws {
        var memory = try afterMonday().memory
        _ = try apply(MemoryWeek.wednesdayReply, for: wednesday, to: &memory)
        #expect(memory.thoughts["running"] != nil)

        MemoryApplier.remove(entryID: MemoryWeek.monday.id, from: &memory)

        // "The launch" also had evidence from Wednesday, so it stays; the Monday-only thoughts go.
        #expect(Set(memory.thoughts.keys) == ["the-launch", "running", "arjun"])
        #expect(memory.thoughts["the-launch"]?.evidence.map(\.date) == ["2026-11-04"])
    }

    @Test func theFileNameOfANoteThatCouldNotBeReadIsNeverReused() throws {
        var memory = MemorySnapshot()
        memory.unreadableIDs = ["meera"]

        _ = try apply(MemoryWeek.mondayReply, for: monday, to: &memory)

        #expect(memory.thoughts["meera"] == nil)
        #expect(memory.thoughts["meera-2"]?.label == "Meera")
    }
}
