//
//  ContextBuilderTests.swift
//  freewriteTests
//
//  Checks what talk is given from memory: the right thoughts, with dated
//  quotes from earlier entries, and nothing when memory is off. Uses the
//  made-up week of entries.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct ContextBuilderTests {

    /// A new entry, written after the made-up week, that memory has not seen.
    private func newEntry(_ text: String) -> TalkEntry {
        TalkEntry(id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!, text: text, date: MemoryWeek.day(10))
    }

    private func build(
        _ entry: TalkEntry,
        said messages: [String] = [],
        limits: ContextBuilder.Limits = ContextBuilder.Limits()
    ) throws -> TalkMemoryContext {
        let built = try MemoryWeek.built()
        return ContextBuilder.build(entry: entry, recentMessages: messages, memory: built.memory, digests: built.digests, limits: limits)
    }

    // MARK: - Which thoughts are picked

    @Test func aThoughtNamedInTheEntryIsPickedWithItsDatedQuotes() throws {
        let context = try build(newEntry("Meera wants an answer today and I still don't have one."))

        let meera = try #require(context.thoughts.first)
        #expect(meera.id == "meera")
        #expect(meera.kind == .person)
        #expect(meera.quotes == [
            TalkMemoryContext.Quote(date: "2026-11-02", text: "I keep replaying the call with Meera about the launch."),
            TalkMemoryContext.Quote(date: "2026-11-06", text: "Meera asked if I could also take the pricing page."),
            TalkMemoryContext.Quote(date: "2026-11-08", text: "I kept drafting the reply to Meera in my head"),
        ])
        #expect(context.profile.hasPrefix("They are in the middle of a launch at work led by Meera."))
    }

    @Test func thoughtsLinkedToItComeAlongWithTheReason() throws {
        let context = try build(newEntry("Meera wants an answer today."))
        let ids = context.thoughts.map(\.id)

        // Two thoughts link to Meera, so they are sent as neighbours, after her.
        #expect(ids.first == "meera")
        #expect(Set(ids.dropFirst()) == ["saying-yes-under-pressure", "the-pricing-page"])

        let pricing = try #require(context.thoughts.first { $0.id == "the-pricing-page" })
        #expect(pricing.connections == [
            TalkMemoryContext.Connection(label: "Meera", reason: "asked for by", date: "2026-11-06", quote: "Meera asked if I could also take the pricing page."),
        ])
        #expect(pricing.shifts == [TalkMemoryContext.Shift(date: "2026-11-08", note: "Leaning towards saying no.")])
    }

    @Test func aThoughtIsFoundByItsOtherNamesAndWithoutItsLeadingThe() throws {
        let byAlias = try build(newEntry("I just can't say no, can I."))
        #expect(byAlias.thoughts.first?.id == "saying-yes-under-pressure")

        let withoutArticle = try build(newEntry("Launch day is finally here."))
        #expect(withoutArticle.thoughts.first?.id == "the-launch")
    }

    @Test func whatWasJustSaidCountsForMoreThanWhatIsOnThePage() throws {
        let context = try build(newEntry("Thinking about the launch again."), said: ["Honestly it's Arjun I want to talk about."])

        #expect(context.thoughts.map(\.id).prefix(2) == ["arjun", "the-launch"])
    }

    @Test func namesAreMatchedAsWholeWords() throws {
        let context = try build(newEntry("We watched a film about Meerabai, then went running shoes shopping."))

        #expect(!context.thoughts.contains { $0.id == "meera" })
        #expect(context.thoughts.contains { $0.id == "running" })
    }

    @Test func thoughtsTheOpenEntryWasFoundToTouchArePickedEvenIfNotNamed() throws {
        // Friday's entry never says "sleep" as a name, but its digest touched "trouble-sleeping".
        let friday = TalkEntry(id: MemoryWeek.friday.id, text: MemoryWeek.friday.text, date: MemoryWeek.friday.startedAt)
        let context = try build(friday)

        #expect(context.thoughts.contains { $0.id == "trouble-sleeping" })
    }

    // MARK: - Only the past is sent

    @Test func linesFromTheOpenEntryAreLeftOut() throws {
        let friday = TalkEntry(id: MemoryWeek.friday.id, text: MemoryWeek.friday.text, date: MemoryWeek.friday.startedAt)
        let context = try build(friday)

        let fridayDay = "2026-11-06"
        for thought in context.thoughts {
            #expect(!thought.quotes.contains { $0.date == fridayDay }, "\(thought.id) sent a line from the open entry")
            #expect(!thought.shifts.contains { $0.date == fridayDay })
            #expect(!thought.connections.contains { $0.date == fridayDay })
        }
        #expect(!context.days.contains { $0.date == fridayDay })

        // Meera still comes with what was written on other days.
        #expect(context.thoughts.first { $0.id == "meera" }?.quotes.map(\.date) == ["2026-11-02", "2026-11-08"])
    }

    @Test func aThoughtKnownOnlyFromTheOpenEntryIsNotSent() throws {
        // "Running" and "Arjun" come only from Wednesday's entry.
        let wednesday = TalkEntry(id: MemoryWeek.wednesday.id, text: MemoryWeek.wednesday.text, date: MemoryWeek.wednesday.startedAt)
        let context = try build(wednesday)

        #expect(!context.thoughts.contains { $0.id == "running" })
        #expect(!context.thoughts.contains { $0.id == "arjun" })
        #expect(context.thoughts.contains { $0.id == "the-launch" })
    }

    @Test func theEntriesBehindTheQuotesAreSummarised() throws {
        let context = try build(newEntry("Meera wants an answer today."))

        #expect(context.days.map(\.date) == ["2026-11-02", "2026-11-06", "2026-11-08"])
        #expect(context.days.first?.summary.hasPrefix("A sleepless night after a call with Meera") == true)
    }

    // MARK: - Nothing to say, and limits

    @Test func whenNothingIsNamedOnlyTheProfileIsSent() throws {
        let context = try build(newEntry("The weather turned today. First cold morning."))

        #expect(context.thoughts.isEmpty)
        #expect(context.days.isEmpty)
        #expect(!context.profile.isEmpty)
        #expect(!context.isEmpty)
    }

    @Test func anEmptyMemoryGivesNothing() {
        let context = ContextBuilder.build(entry: newEntry("Meera again."), recentMessages: [], memory: MemorySnapshot(), digests: [])

        #expect(context.isEmpty)
    }

    @Test func theCapsHold() throws {
        var limits = ContextBuilder.Limits()
        limits.named = 1
        limits.neighbours = 1
        limits.quotesPerThought = 1
        limits.daySummaries = 1

        let context = try build(newEntry("Meera, the launch, the pricing page, running, Arjun."), limits: limits)

        #expect(context.thoughts.count == 2)
        #expect(context.thoughts.allSatisfy { $0.quotes.count == 1 })
        #expect(context.days.count == 1)
        // The most recent line is the one kept.
        #expect(context.thoughts.first?.quotes.first?.date == "2026-11-08")
    }

    @Test func aSmallSizeLimitDropsTheLeastRelevantFirst() throws {
        var limits = ContextBuilder.Limits()
        limits.maxCharacters = 700

        let context = try build(newEntry("Meera wants an answer today."), limits: limits)

        // Neighbours go first; the thought that was actually named stays.
        #expect(context.thoughts.map(\.id) == ["meera"])
    }

    // MARK: - How it is laid out for the model

    @Test func theNotesNameEachDayInFullAndQuoteTheEntry() throws {
        let context = try build(newEntry("Meera wants an answer today."))
        let notes = Prompts.talkMemoryNotes(context)

        #expect(notes.hasPrefix("These are the notes from their earlier entries.\n\n<memory>\nProfile:\n"))
        #expect(notes.hasSuffix("\n</memory>"))
        #expect(notes.contains("Meera (person). A colleague leading the launch, whose requests are hard to refuse."))
        #expect(notes.contains("- Monday 2 November 2026, they wrote: \"I keep replaying the call with Meera about the launch.\""))
        #expect(notes.contains("- How it shifted, Sunday 8 November 2026: Leaning towards saying no."))
        #expect(notes.contains("- Linked to Meera (asked for by), Friday 6 November 2026: \"Meera asked if I could also take the pricing page.\""))
        #expect(notes.contains("What those entries were about:\n- Monday 2 November 2026: A sleepless night"))
    }

    @Test func withMemoryTheInstructionsSayToNameTheDayAndStateNothingElse() throws {
        let context = try build(newEntry("Meera wants an answer today."))
        let system = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10), memory: context)

        #expect(system.hasPrefix(Prompts.talkVoiceWithMemory))
        #expect(system.contains("name the day it was written"))
        #expect(system.contains("State nothing about their past that is not in the notes or the entry."))
        #expect(system.contains("Never recite the profile"))
        #expect(!system.contains("You cannot see their other entries."))
        // The safety behaviour is unchanged.
        #expect(system.contains("Tele-MANAS on 14416"))
        // Order: voice, then memory, then the entry.
        let memoryAt = try #require(system.range(of: "<memory>"))
        let entryAt = try #require(system.range(of: "<entry>"))
        #expect(memoryAt.lowerBound < entryAt.lowerBound)
    }

    @Test func withoutMemoryTheInstructionsAreExactlyAsBefore() {
        let plain = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10))
        let withNothing = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10), memory: TalkMemoryContext())

        #expect(plain == withNothing)
        #expect(plain.hasPrefix(Prompts.talkVoice))
        #expect(plain.contains("You cannot see their other entries."))
        #expect(!plain.contains("<memory>"))
    }
}

@MainActor
@Suite struct TalkWithMemoryTests {

    private let entry = TalkEntry(
        id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
        text: "Meera wants an answer today and I still don't have one.",
        date: MemoryWeek.day(10)
    )

    @Test func withMemoryOnTalkIsGivenTheNotesAndTheDays() async throws {
        let sandbox = TalkSandbox()
        try sandbox.writeMadeUpMemory()
        sandbox.settings.memoryEnabled = true
        let provider = FakeProvider([.reply(["On Monday you wrote about the call."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: entry)
        await talk.replyTask?.value

        let system = try #require(provider.requests.first?.system)
        #expect(system.hasPrefix(Prompts.talkVoiceWithMemory))
        #expect(system.contains("<memory>"))
        #expect(system.contains("Monday 2 November 2026, they wrote: \"I keep replaying the call with Meera about the launch.\""))
        #expect(system.contains("<entry>\nMeera wants an answer today and I still don't have one.\n</entry>"))
        #expect(talk.transcript.messages.map(\.text) == ["On Monday you wrote about the call."])
    }

    @Test func somethingSaidInTheColumnBringsItsThoughtAlong() async throws {
        let sandbox = TalkSandbox()
        try sandbox.writeMadeUpMemory()
        sandbox.settings.memoryEnabled = true
        let provider = FakeProvider([.reply(["Reply."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("I went running again this morning.")
        await talk.replyTask?.value

        let system = try #require(provider.requests.first?.system)
        #expect(system.contains("Running (idea)."))
        #expect(system.contains("Wednesday 4 November 2026, they wrote: \"Went for a run before work for the first time in weeks.\""))
    }

    @Test func withMemoryOffNothingFromMemoryIsSent() async throws {
        let sandbox = TalkSandbox()
        try sandbox.writeMadeUpMemory()
        sandbox.settings.memoryEnabled = false
        let provider = FakeProvider([.reply(["Reply."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: entry)
        await talk.replyTask?.value

        let system = try #require(provider.requests.first?.system)
        #expect(system == Prompts.talkSystem(entryText: entry.text, entryDate: entry.date))
        #expect(!system.contains("<memory>"))
        #expect(!system.contains("I keep replaying the call"))
    }

    @Test func withMemoryOnButNothingBuiltYetTalkIsAsBefore() async throws {
        let sandbox = TalkSandbox()
        sandbox.settings.memoryEnabled = true
        let provider = FakeProvider([.reply(["Reply."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: entry)
        await talk.replyTask?.value

        #expect(provider.requests.first?.system == Prompts.talkSystem(entryText: entry.text, entryDate: entry.date))
    }
}
