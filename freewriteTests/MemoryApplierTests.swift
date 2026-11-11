//
//  MemoryApplierTests.swift
//  freewriteTests
//
//  Checks the step that decides what from a reading of an entry is allowed
//  into memory, and in what form: no invented quotes, the user's fixes win,
//  reuse before create, applying the same entry twice changes nothing, people
//  and topics become thoughts, and feelings and what the writer told
//  themselves stay on the day in their own words. Uses the made-up week.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct MemoryApplierTests {

    private let monday = MemoryWeek.digested(MemoryWeek.monday)
    private let wednesday = MemoryWeek.digested(MemoryWeek.wednesday)
    private let friday = MemoryWeek.digested(MemoryWeek.friday)
    private let sunday = MemoryWeek.digested(MemoryWeek.sunday)

    /// Memory after Monday's entry has been read.
    private func afterMonday(pins: Pins = Pins()) throws -> (memory: MemorySnapshot, outcome: MemoryApplier.Outcome) {
        var memory = MemorySnapshot()
        let outcome = MemoryApplier.apply(try DigestParser.parse(MemoryWeek.mondayReply), for: monday, to: &memory, pins: pins)
        return (memory, outcome)
    }

    private func apply(_ reply: String, for entry: DigestedEntry, to memory: inout MemorySnapshot, pins: Pins = Pins()) throws -> MemoryApplier.Outcome {
        MemoryApplier.apply(try DigestParser.parse(reply), for: entry, to: &memory, pins: pins)
    }

    /// Memory after the whole week, in order.
    private func afterTheWeek(pins: Pins = Pins()) throws -> (memory: MemorySnapshot, outcomes: [MemoryApplier.Outcome]) {
        var memory = MemorySnapshot()
        var outcomes: [MemoryApplier.Outcome] = []
        for (entry, reply) in zip(MemoryWeek.entries, MemoryWeek.replies) {
            outcomes.append(try apply(reply, for: MemoryWeek.digested(entry), to: &memory, pins: pins))
        }
        return (memory, outcomes)
    }

    // MARK: - What becomes a thought, and what stays on the day

    @Test func peopleAndTopicsBecomeThoughtsWithTheEntrysOwnWords() throws {
        let (memory, outcome) = try afterMonday()

        #expect(Set(memory.thoughts.keys) == ["meera", "the-launch"])
        #expect(outcome.touched == ["meera", "the-launch"])
        #expect(memory.thoughts["meera"]?.kind == .person)
        #expect(memory.thoughts["the-launch"]?.kind == .topic)
        #expect(memory.thoughts["meera"]?.evidence == [Evidence(entryID: MemoryWeek.monday.id, date: "2026-11-02", quote: "the call with Meera")])
        // Nothing is written about them by the AI: no description, no notes, no profile.
        #expect(memory.thoughts.values.allSatisfy { $0.summary.isEmpty && $0.timeline.isEmpty })
        #expect(memory.profile.isEmpty)
    }

    @Test func feelingsAndWhatTheyToldThemselvesStayOnTheDayInTheirOwnWords() throws {
        let outcome = try afterMonday().outcome

        #expect(outcome.lines == [
            // The reply quoted it with a straight apostrophe; the entry's curly one is what is kept.
            DayLine(kind: .felt, quote: "Couldn’t sleep again.", word: "Couldn't sleep", tone: .unpleasant),
            DayLine(kind: .felt, quote: "felt sick about it for the rest of the day", word: "felt sick", tone: .unpleasant),
            DayLine(kind: .happened, quote: "I said yes to everything she asked"),
            DayLine(kind: .toldYourself, quote: "I don't even know what I was afraid of."),
        ])
    }

    @Test func aQuoteThatIsNotInTheEntryIsRefused() throws {
        let (memory, outcome) = try afterMonday()

        // "I am terrified of failing at this." was never written.
        #expect(!outcome.lines.contains { $0.word == "terrified" })
        #expect(outcome.rejected == [EntryDigest.Rejection(item: "feeling", reason: "Its quote is not in the entry.")])
        #expect(memory.thoughts.count == 2)
    }

    @Test func aFeelingWordThatIsNotTheirsIsNotKeptAsTheirWord() throws {
        var memory = MemorySnapshot()
        // The line is theirs; "anxious" is the model's word for it.
        let reply = DigestJSON.reply(feelings: [DigestJSON.felt("anxious", "unpleasant", "Still felt my stomach drop")])
        let outcome = try apply(reply, for: friday, to: &memory)

        #expect(outcome.lines == [DayLine(kind: .felt, quote: "Still felt my stomach drop", word: nil, tone: .unpleasant)])
        #expect(outcome.rejected.isEmpty)
    }

    @Test func everyThoughtLinkAndLineCarriesWordsFoundInItsEntry() throws {
        let (memory, outcomes) = try afterTheWeek()
        let texts = Dictionary(uniqueKeysWithValues: MemoryWeek.entries.map { ($0.id, $0.text) })

        for thought in memory.thoughts.values {
            #expect(!thought.evidence.isEmpty, "\(thought.id) has no evidence")
            for item in thought.evidence {
                #expect(texts[item.entryID]?.contains(item.quote) == true, "\(thought.id): evidence not in its entry")
            }
            for link in thought.links {
                #expect(texts[link.entryID]?.contains(link.quote) == true, "\(thought.id): link quote not in its entry")
                #expect(memory.thoughts[link.target] != nil, "\(thought.id): link points nowhere")
            }
        }
        for (entry, outcome) in zip(MemoryWeek.entries, outcomes) {
            #expect(!outcome.lines.isEmpty)
            for line in outcome.lines {
                #expect(entry.text.contains(line.quote), "a line is not in its entry")
            }
        }
    }

    // MARK: - What helped, and what is still open

    @Test func whatHelpedIsKeptOnlyWhenTheEntryPutsItWithAPleasantFeeling() throws {
        var memory = try afterMonday().memory
        let outcome = try apply(MemoryWeek.wednesdayReply, for: wednesday, to: &memory)

        let run = try #require(memory.thoughts["a-run-before-work"])
        #expect(run.kind == .helped)
        #expect(run.evidence.map(\.quote) == ["Went for a run before work for the first time in weeks. Legs felt heavy but my head was quiet afterwards."])
        #expect(outcome.lines.contains(DayLine(kind: .helped, quote: "Went for a run before work for the first time in weeks. Legs felt heavy but my head was quiet afterwards.")))
        #expect(outcome.rejected.isEmpty)
    }

    @Test func theAIsSaySoIsNotEnoughForWhatHelped() throws {
        var memory = MemorySnapshot()
        // Nothing in the entry says telling Arjun made anything better.
        let reply = DigestJSON.reply(
            feelings: [DigestJSON.felt("quiet", "pleasant", "my head was quiet afterwards")],
            helped: [DigestJSON.noted("telling Arjun", "Told Arjun I might skip the Friday review and he just laughed.")]
        )
        let outcome = try apply(reply, for: wednesday, to: &memory)

        #expect(memory.thoughts.isEmpty)
        #expect(outcome.rejected == [EntryDigest.Rejection(item: "helped", reason: "The entry does not say they felt better.")])
        #expect(!outcome.lines.contains { $0.kind == .helped })
    }

    @Test func somethingStillOpenIsNamedByTheirOwnLine() throws {
        let (memory, outcomes) = try afterTheWeek()

        let open = memory.thoughts.values.filter { $0.kind == .open }.sorted { $0.id < $1.id }
        #expect(open.map(\.label) == ["I said I needed to think about it", "Need to tell her by Tuesday"])
        #expect(open.map(\.id) == ["i-said-i-needed-to-think-about-it", "need-to-tell-her-by-tuesday"])
        #expect(open.last?.evidence == [Evidence(entryID: MemoryWeek.sunday.id, date: "2026-11-08", quote: "Need to tell her by Tuesday.")])
        #expect(outcomes[3].lines.contains(DayLine(kind: .stillOpen, quote: "Need to tell her by Tuesday.")))
        // What they said they want is a line on the day, not a thought.
        #expect(outcomes[3].lines.contains(DayLine(kind: .wanted, quote: "I think I already know I don't want the pricing page.")))
    }

    @Test func anOpenLabelIsTheirLineWithoutItsFullStopAndNotTooLong() {
        #expect(MemoryApplier.openLabel("Need to tell her\n by Tuesday.") == "Need to tell her by Tuesday")
        #expect(MemoryApplier.openLabel("Call Ma back?!") == "Call Ma back")
        let long = String(repeating: "I still need to decide about the flat and ", count: 4)
        #expect(MemoryApplier.openLabel(long).count == 91)
        #expect(MemoryApplier.openLabel(long).hasSuffix("…"))
    }

    // MARK: - Reuse before create

    @Test func theSameNameAgainJoinsTheExistingThought() throws {
        let memory = try afterTheWeek().memory

        // Meera is in three entries and is one thought.
        #expect(memory.thoughts["meera"]?.evidence.map(\.date) == ["2026-11-02", "2026-11-06", "2026-11-08"])
        #expect(memory.thoughts["the-launch"]?.evidence.count == 2)
        #expect(memory.thoughts["the-launch"]?.firstSeen == "2026-11-02")
        #expect(memory.thoughts["the-launch"]?.lastSeen == "2026-11-04")
    }

    @Test func aNameWithoutItsArticleIsTheSameThing() throws {
        let memory = try afterTheWeek().memory

        // Sunday's reply said "pricing page"; memory already had "the pricing page".
        #expect(memory.thoughts["pricing-page"] == nil)
        let pricing = try #require(memory.thoughts["the-pricing-page"])
        #expect(pricing.label == "the pricing page")
        #expect(pricing.aliases == ["pricing page"])
        #expect(pricing.evidence.count == 2)
    }

    @Test func theSameNameInDifferentCapitalsOrPunctuationIsTheSameThought() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(
            people: [DigestJSON.named("MEERA!", "Meera asked if I could also take the pricing page.")],
            topics: [DigestJSON.named("Launch", "Meera asked if I could also take the pricing page.")]
        )
        let outcome = try apply(reply, for: friday, to: &memory)

        #expect(memory.thoughts.count == 2)
        #expect(outcome.touched == ["meera", "the-launch"])
        #expect(memory.thoughts["meera"]?.evidence.count == 2)
    }

    @Test func anItemWithNoNameIsRefused() throws {
        var memory = MemorySnapshot()
        let outcome = try apply(DigestJSON.reply(people: [DigestJSON.named("  ", "Told Arjun I might skip the Friday review")]), for: wednesday, to: &memory)

        #expect(memory.thoughts.isEmpty)
        #expect(outcome.rejected == [EntryDigest.Rejection(item: "person", reason: "It had no name.")])
    }

    // MARK: - Links

    @Test func twoThoughtsInTheSameSentenceAreLinkedAndOthersAreNot() throws {
        let memory = try afterTheWeek().memory

        // "the call with Meera about the launch": one sentence names both.
        #expect(memory.thoughts["meera"]?.links.contains {
            $0.target == "the-launch" && $0.reason == MemoryApplier.sameSentence && $0.quote == "the call with Meera about the launch"
        } == true)
        // "Meera asked if I could also take the pricing page."
        #expect(memory.thoughts["meera"]?.links.contains { $0.target == "the-pricing-page" && $0.entryID == MemoryWeek.friday.id } == true)
        // Arjun and the Friday review share a line too.
        #expect(memory.thoughts["arjun"]?.links.map(\.target) == ["the-friday-review"])
        // On Sunday Meera and the pricing page are in different sentences: the day joins them, not a link.
        #expect(memory.thoughts["meera"]?.links.contains { $0.entryID == MemoryWeek.sunday.id } == false)
        // A thought is never linked to itself, and each link goes one way only.
        for thought in memory.thoughts.values {
            #expect(!thought.links.contains { $0.target == thought.id })
            for link in thought.links {
                #expect(thought.id < link.target)
            }
        }
    }

    // MARK: - The user's fixes win

    @Test func aDeletedThoughtCannotComeBackOrBeAddedTo() throws {
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "meera", label: "Meera")]

        let (memory, outcome) = try afterMonday(pins: pins)

        #expect(memory.thoughts["meera"] == nil)
        #expect(outcome.rejected.contains(EntryDigest.Rejection(item: "person", reason: "You deleted this thought.")))
        #expect(outcome.touched == ["the-launch"])
    }

    @Test func aThoughtDeletedInPinsIsRemovedEvenIfItsNoteIsStillThere() throws {
        var memory = try afterMonday().memory
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "the-launch", label: "the launch")]

        _ = try apply(DigestJSON.reply(), for: wednesday, to: &memory, pins: pins)

        #expect(memory.thoughts["the-launch"] == nil)
        #expect(memory.thoughts["meera"]?.links.isEmpty == true)
    }

    @Test func aMergedAwayThoughtSendsItsEvidenceToTheOneItJoined() throws {
        var pins = Pins()
        pins.merges = [Pins.Merge(from: "the-friday-review", into: "the-launch")]
        var memory = try afterMonday(pins: pins).memory

        let outcome = try apply(MemoryWeek.wednesdayReply, for: wednesday, to: &memory, pins: pins)

        #expect(memory.thoughts["the-friday-review"] == nil)
        #expect(memory.thoughts["the-launch"]?.evidence.map(\.quote).contains("Told Arjun I might skip the Friday review") == true)
        #expect(outcome.touched.contains("the-launch"))
    }

    @Test func aRenameIsKept() throws {
        var pins = Pins()
        pins.renames = [Pins.Rename(id: "meera", label: "Meera (work)")]

        let memory = try afterMonday(pins: pins).memory

        #expect(memory.thoughts["meera"]?.label == "Meera (work)")
        #expect(memory.thoughts["meera"]?.aliases == ["Meera"])
    }

    @Test func aLinkTheUserRemovedIsNotPutBack() throws {
        var pins = Pins()
        pins.linksRemoved = [Pins.LinkPin(from: "the-launch", to: "meera", reason: nil)]

        let (memory, outcome) = try afterMonday(pins: pins)

        #expect(memory.thoughts["meera"]?.links.isEmpty == true)
        #expect(outcome.rejected.contains(EntryDigest.Rejection(item: "link", reason: "You removed this link.")))
    }

    @Test func somethingTheUserClosedStaysOffTheMapButItsLineStaysOnTheDay() throws {
        var pins = Pins()
        pins.deletions = [Pins.Deletion(id: "need-to-tell-her-by-tuesday", label: "Need to tell her by Tuesday", settled: "done", on: "2026-11-10")]

        var memory = MemorySnapshot()
        let outcome = try apply(MemoryWeek.sundayReply, for: sunday, to: &memory, pins: pins)

        #expect(memory.thoughts["need-to-tell-her-by-tuesday"] == nil)
        #expect(outcome.lines.contains(DayLine(kind: .stillOpen, quote: "Need to tell her by Tuesday.")))
        #expect(!outcome.rejected.contains { $0.item == "open_loop" })
        #expect(pins.settled(forLine: "Need to tell her by Tuesday.") == .done)
        #expect(pins.settled(forLine: "Something else entirely") == nil)
    }

    // MARK: - Doing it twice changes nothing

    @Test func applyingTheSameReadingTwiceGivesTheSameMemory() throws {
        var memory = try afterMonday().memory
        let once = memory
        let again = try apply(MemoryWeek.mondayReply, for: monday, to: &memory)

        #expect(memory == once)
        #expect(again == (try afterMonday().outcome))
    }

    @Test func aChangedReadingForTheSameEntryReplacesItsOldLines() throws {
        var memory = try afterMonday().memory
        let reply = DigestJSON.reply(people: [DigestJSON.named("Meera", "I keep replaying the call with Meera about the launch.")])
        let outcome = try apply(reply, for: monday, to: &memory)

        #expect(Set(memory.thoughts.keys) == ["meera"])
        #expect(memory.thoughts["meera"]?.evidence.map(\.quote) == ["I keep replaying the call with Meera about the launch."])
        #expect(outcome.lines.isEmpty)
    }

    @Test func removingAnEntryTakesOnlyItsLinesAndDropsThoughtsLeftWithNone() throws {
        var memory = try afterTheWeek().memory
        MemoryApplier.remove(entryID: MemoryWeek.wednesday.id, from: &memory)

        // Only Wednesday named these.
        #expect(memory.thoughts["arjun"] == nil)
        #expect(memory.thoughts["a-run-before-work"] == nil)
        #expect(memory.thoughts["the-friday-review"] == nil)
        // The launch was also in Monday's entry.
        #expect(memory.thoughts["the-launch"]?.evidence.map(\.date) == ["2026-11-02"])
        #expect(memory.thoughts["meera"]?.evidence.count == 3)
    }

    @Test func theFileNameOfANoteThatCouldNotBeReadIsNeverReused() throws {
        var memory = MemorySnapshot()
        memory.unreadableIDs = ["meera"]

        let outcome = try apply(MemoryWeek.mondayReply, for: monday, to: &memory)

        #expect(memory.thoughts["meera"] == nil)
        #expect(memory.thoughts["meera-2"]?.label == "Meera")
        #expect(outcome.touched == ["meera-2", "the-launch"])
    }
}

@Suite struct FeelingDotsTests {

    private func digest(_ number: Int, day: String, _ lines: [DayLine], failed: Bool = false) -> EntryDigest {
        EntryDigest(
            entryID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
            entryDate: day,
            textHash: "made-up",
            digestedAt: MemoryWeek.day(20),
            model: "model-for-memory",
            summary: "",
            thoughts: [],
            openLoops: [],
            rejected: [],
            inputTokens: nil,
            outputTokens: nil,
            failed: failed,
            failureReason: nil,
            lines: lines
        )
    }

    private func felt(_ word: String?, _ quote: String, _ tone: DayLine.Tone = .unpleasant) -> DayLine {
        DayLine(kind: .felt, quote: quote, word: word, tone: tone)
    }

    @Test func aFeelingNamedOnceStaysOnItsDay() {
        var memory = MemorySnapshot()
        FeelingDots.reconcile(&memory, with: [digest(1, day: "2026-11-11", [felt("tired", "I'm tired all the time")])], pins: Pins())

        #expect(memory.thoughts.isEmpty)
    }

    @Test func theSameWordsOnTwoDaysBecomeAThoughtWithBothLines() throws {
        var memory = MemorySnapshot()
        let digests = [
            digest(1, day: "2026-11-11", [felt("tired", "I'm tired all the time")]),
            digest(2, day: "2026-11-22", [felt("so tired", "I'm so tired of all of it.")]),
            digest(3, day: "2026-11-23", [felt("slept fine", "but I slept fine.", .pleasant)]),
        ]
        FeelingDots.reconcile(&memory, with: digests, pins: Pins())

        #expect(Array(memory.thoughts.keys) == ["felt-tired"])
        let tired = try #require(memory.thoughts["felt-tired"])
        #expect(tired.kind == .feeling)
        // Named by the first words used; later wordings are its other names.
        #expect(tired.label == "tired")
        #expect(tired.aliases == ["so tired"])
        #expect(tired.evidence.map(\.quote) == ["I'm tired all the time", "I'm so tired of all of it."])
        #expect(FeelingDots.touched(by: digests[1].entryID, in: memory) == ["felt-tired"])
        #expect(FeelingDots.touched(by: digests[2].entryID, in: memory).isEmpty)

        // Doing it again changes nothing.
        let once = memory
        FeelingDots.reconcile(&memory, with: digests, pins: Pins())
        #expect(memory == once)
    }

    @Test func wordsInFrontThatDoNotChangeTheFeelingAreIgnored() {
        #expect(FeelingDots.key("So tired") == "tired")
        #expect(FeelingDots.key("felt sick") == "sick")
        #expect(FeelingDots.key("a bit low") == "low")
        #expect(FeelingDots.key("Couldn’t sleep") == "couldnt sleep")
        // Different feelings stay different, and a single word is never emptied.
        #expect(FeelingDots.key("slept fine") != FeelingDots.key("slept badly"))
        #expect(FeelingDots.key("so") == "so")
    }

    @Test func aFeelingWithoutTheirOwnWordIsNeverCounted() {
        var memory = MemorySnapshot()
        let digests = [
            digest(1, day: "2026-11-11", [felt(nil, "Still felt my stomach drop")]),
            digest(2, day: "2026-11-12", [felt(nil, "Still felt my stomach drop")]),
        ]
        FeelingDots.reconcile(&memory, with: digests, pins: Pins())

        #expect(memory.thoughts.isEmpty)
    }

    @Test func whenADayGoesTheFeelingGoesBackToBeingALine() {
        var memory = MemorySnapshot()
        let first = digest(1, day: "2026-11-11", [felt("tired", "I'm tired all the time")])
        let second = digest(2, day: "2026-11-22", [felt("tired", "I'm so tired of all of it.")])
        FeelingDots.reconcile(&memory, with: [first, second], pins: Pins())
        #expect(memory.thoughts["felt-tired"] != nil)

        // The second entry is deleted: its lines are taken out, as the engine does, then the count is redone.
        MemoryApplier.remove(entryID: second.entryID, from: &memory)
        FeelingDots.reconcile(&memory, with: [first], pins: Pins())

        #expect(memory.thoughts.isEmpty)
    }

    @Test func anEntryThatCouldNotBeReadIsNotCounted() {
        var memory = MemorySnapshot()
        let digests = [
            digest(1, day: "2026-11-11", [felt("tired", "I'm tired all the time")]),
            digest(2, day: "2026-11-22", [felt("tired", "I'm so tired of all of it.")], failed: true),
        ]
        FeelingDots.reconcile(&memory, with: digests, pins: Pins())

        #expect(memory.thoughts.isEmpty)
    }

    @Test func theUsersFixesHoldForFeelingsToo() throws {
        let digests = [
            digest(1, day: "2026-11-11", [felt("tired", "I'm tired all the time")]),
            digest(2, day: "2026-11-22", [felt("tired", "I'm so tired of all of it.")]),
        ]

        // Deleted: it does not come back.
        var deleted = Pins()
        deleted.deletions = [Pins.Deletion(id: "felt-tired", label: "tired")]
        var memory = MemorySnapshot()
        FeelingDots.reconcile(&memory, with: digests, pins: deleted)
        #expect(memory.thoughts.isEmpty)

        // Renamed: it keeps the user's name.
        var renamed = Pins()
        renamed.renames = [Pins.Rename(id: "felt-tired", label: "worn out", names: ["tired"])]
        memory = MemorySnapshot()
        FeelingDots.reconcile(&memory, with: digests, pins: renamed)
        #expect(memory.thoughts["felt-tired"]?.label == "worn out")

        // Folded into another thought: its lines go there.
        var merged = Pins()
        merged.merges = [Pins.Merge(from: "felt-tired", into: "sleep", names: ["tired"], intoLabel: "sleep")]
        memory = MemorySnapshot()
        memory.thoughts["sleep"] = Thought(id: "sleep", label: "sleep", kind: .topic, evidence: [
            Evidence(entryID: digests[0].entryID, date: "2026-11-11", quote: "Slept at nine."),
        ])
        FeelingDots.reconcile(&memory, with: digests, pins: merged)
        #expect(memory.thoughts["felt-tired"] == nil)
        #expect(memory.thoughts["sleep"]?.evidence.count == 3)
    }
}
