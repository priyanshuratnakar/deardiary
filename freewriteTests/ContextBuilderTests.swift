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

    @Test func theNotesAreNumberedLinesInTheWritersOwnWords() throws {
        let context = try build(newEntry("Meera wants an answer today."))
        let notes = Prompts.talkMemoryNotes(context)
        let lines = Prompts.earlierLines(from: context)

        #expect(notes.hasPrefix("These are lines from their earlier entries.\n\n<earlier>\nProfile (background only):\n"))
        #expect(notes.hasSuffix("\n</earlier>"))

        // Numbered from 1, each with its day in full, what it was about, and the entry's own words.
        #expect(!lines.isEmpty)
        #expect(lines.map(\.number) == Array(1...lines.count))
        for line in lines {
            #expect(notes.contains("{\(line.number)} \(Prompts.longDay(line.date)), \(line.label): \"\(line.quote)\""))
        }
        let replaying = try #require(lines.first { $0.quote == "I keep replaying the call with Meera about the launch." })
        #expect(replaying.date == "2026-11-02")
        #expect(notes.contains("Monday 2 November 2026, about "))

        // What the AI wrote about a thought is not sent: only what can be shown word for word.
        #expect(!notes.contains("A colleague leading the launch"))
        #expect(!notes.contains("How it shifted"))
        #expect(!notes.contains("What those entries were about"))
    }

    @Test func whatTheyToldThemselvesOnThoseDaysIsOfferedToo() throws {
        // Memory in the shape of a journal: the day's own lines are kept with each entry.
        let read = try MemoryWeek.read()
        let entry = newEntry("Meera wants an answer today and I still don't have one.")
        let context = ContextBuilder.build(entry: entry, recentMessages: [], memory: read.memory, digests: read.digests)
        let lines = Prompts.earlierLines(from: context)

        // The line worth bringing up is often not the one that names the person.
        let said = try #require(lines.first { $0.quote == "First time I haven't just said yes." })
        #expect(said.date == "2026-11-06")
        #expect(said.label == "what they told themselves, on a day they wrote about Meera")
        let wanted = try #require(lines.first { $0.quote == "I think I already know I don't want the pricing page." })
        #expect(wanted.label.hasPrefix("what they told themselves, on a day they wrote about "))
        // One line from each day she was written about, so one day does not crowd out the others.
        #expect(lines.filter { $0.label.hasSuffix("about Meera") }.map(\.date) == ["2026-11-02", "2026-11-06", "2026-11-08"])
        #expect(lines.contains { $0.quote == "I don't even know what I was afraid of." })
        // What happened is not offered: it is the least telling kind of line.
        #expect(!lines.contains { $0.quote == "I said yes to everything she asked" })
        // Each line is offered once, however many thoughts share its day.
        #expect(Set(lines.map { $0.date + $0.quote }).count == lines.count)

        let notes = Prompts.talkMemoryNotes(context)
        #expect(notes.contains("Friday 6 November 2026, what they told themselves, on a day they wrote about Meera: \"First time I haven't just said yes.\""))
        // The profile that goes with them is counted by the app.
        #expect(notes.contains("Profile (background only):\nMost written about in the last month: Meera (3 entries)"))
    }

    @Test func theDaysLinesFromTheOpenEntryAreLeftOut() throws {
        let read = try MemoryWeek.read()
        // Sunday's entry is the one open on the page.
        let entry = TalkEntry(id: MemoryWeek.sunday.id, text: MemoryWeek.sunday.text, date: MemoryWeek.sunday.startedAt)
        let context = ContextBuilder.build(entry: entry, recentMessages: [], memory: read.memory, digests: read.digests)
        let quotes = context.thoughts.flatMap(\.quotes).map(\.text)

        #expect(!quotes.isEmpty)
        #expect(!quotes.contains("Slept badly."))
        #expect(!quotes.contains("I think I already know I don't want the pricing page."))
        #expect(quotes.contains("First time I haven't just said yes."))
    }

    @Test func aLineSaysWhatItIsWhenItIsNotAboutAPersonOrTopic() {
        func item(_ kind: ThoughtKind, _ label: String) -> TalkMemoryContext.Item {
            TalkMemoryContext.Item(id: label, label: label, kind: kind, summary: "", quotes: [TalkMemoryContext.Quote(date: "2026-11-04", text: "A line about \(label).")], shifts: [], connections: [])
        }
        var context = TalkMemoryContext()
        context.thoughts = [item(.person, "Ma"), item(.feeling, "tired"), item(.open, "Call Ma back"), item(.helped, "a run before work"), item(.theme, "Saying yes")]

        #expect(Prompts.earlierLines(from: context).map(\.label) == [
            "about Ma",
            "a day they named feeling tired",
            "something they said was still open",
            "something they wrote had helped (a run before work)",
            "about Saying yes",
        ])
    }

    @Test func noThoughtCrowdsOutTheOthersAndALineIsOfferedOnce() {
        func thought(_ label: String, _ quotes: [(String, String)]) -> TalkMemoryContext.Item {
            TalkMemoryContext.Item(
                id: label.lowercased(), label: label, kind: .theme, summary: "",
                quotes: quotes.map { TalkMemoryContext.Quote(date: $0.0, text: $0.1) }, shifts: [], connections: []
            )
        }
        var context = TalkMemoryContext()
        // Five thoughts with three lines each is more than the limit of twelve.
        context.thoughts = (1...5).map { number in
            thought("Thought \(number)", (1...3).map { ("2026-11-0\($0)", "Line \($0) of thought \(number).") })
        }
        // The same line under a second thought.
        context.thoughts.append(thought("Echo", [("2026-11-03", "Line 3 of thought 1.")]))

        let lines = Prompts.earlierLines(from: context)

        #expect(lines.count == Prompts.earlierLineLimit)
        #expect(lines.map(\.number) == Array(1...12))
        // Every thought keeps its most recent line.
        for number in 1...5 {
            #expect(lines.contains { $0.quote == "Line 3 of thought \(number)." })
        }
        // Listed thought by thought, oldest first.
        #expect(lines.prefix(3).map(\.quote) == ["Line 1 of thought 1.", "Line 2 of thought 1.", "Line 3 of thought 1."])
        // Offered once, under the first thought that has it.
        #expect(lines.filter { $0.quote == "Line 3 of thought 1." }.count == 1)
        #expect(!lines.contains { $0.label == "Echo" })
        #expect(Prompts.earlierLines(from: nil).isEmpty)
    }

    @Test func withMemoryTheInstructionsSayToPointAtALineAndStateNothingElse() throws {
        let context = try build(newEntry("Meera wants an answer today."))
        let system = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10), memory: context)

        #expect(system.hasPrefix(Prompts.talkVoiceWithMemory))
        #expect(system.contains("write its number in curly brackets"))
        #expect(system.contains("Never type out an earlier line yourself, and never state the day yourself."))
        #expect(system.contains("State nothing about their past that is not in these lines or the entry."))
        #expect(system.contains("never recite them"))
        #expect(!system.contains("You cannot see their other entries."))
        // The safety behaviour is the same with memory as without.
        #expect(system.contains(Prompts.talkSafety))
        // Order: voice, then the earlier lines, then the entry.
        let memoryAt = try #require(system.range(of: "<earlier>"))
        let entryAt = try #require(system.range(of: "<entry>"))
        #expect(memoryAt.lowerBound < entryAt.lowerBound)
    }

    @Test func withoutMemoryTheInstructionsAreForTheEntryOnly() {
        let plain = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10))
        let withNothing = Prompts.talkSystem(entryText: "Meera wants an answer today.", entryDate: MemoryWeek.day(10), memory: TalkMemoryContext())

        #expect(plain == withNothing)
        #expect(plain.hasPrefix(Prompts.talkVoice))
        #expect(plain.contains("You cannot see their other entries."))
        #expect(!plain.contains("<earlier>"))
        #expect(!plain.contains("curly brackets"))
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
        #expect(system.contains("<earlier>"))
        #expect(system.contains("} Monday 2 November 2026, about "))
        #expect(system.contains("\"I keep replaying the call with Meera about the launch.\""))
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
        #expect(system.contains("} Wednesday 4 November 2026, about "))
        #expect(system.contains("\"Went for a run before work for the first time in weeks.\""))
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
        #expect(!system.contains("<earlier>"))
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
