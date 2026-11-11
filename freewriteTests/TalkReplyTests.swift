//
//  TalkReplyTests.swift
//  freewriteTests
//
//  The parts of talk the app decides for itself: writing out a line from an
//  earlier entry, the safety net and the help line, and never asking two
//  questions in a row. Every entry and conversation here is made up.
//

import Testing
import Foundation
@testable import freewrite

private let monday = EarlierLine(number: 1, date: "2026-11-02", label: "Meera", quote: "I said yes to everything she asked.")
private let friday = EarlierLine(number: 2, date: "2026-11-06", label: "Saying yes under pressure", quote: "First time I haven't just said yes.")
private let offered = [monday, friday]

/// The instructions a request carried.
private func instructions(_ request: LLMRequest?) -> String {
    request?.system ?? ""
}

@Suite struct TalkReplyTests {

    // MARK: - Earlier lines

    @Test func aNumberBecomesTheLineWordForWordWithItsDay() {
        let shown = TalkReply.shown("{1} Today it's \"I asked him\". What happened in between?", lines: offered, finished: true)

        #expect(shown.text == "> Monday 2 November 2026: \"I said yes to everything she asked.\"\n\nToday it's \"I asked him\". What happened in between?")
        #expect(!shown.flaggedCare)
    }

    @Test func aNumberInTheMiddleOfASentenceStillGetsItsOwnParagraph() {
        let shown = TalkReply.shown("You wrote this once: { 2 } and today it reads the same.", lines: offered, finished: true)

        #expect(shown.text == "You wrote this once:\n\n> Friday 6 November 2026: \"First time I haven't just said yes.\"\n\nand today it reads the same.")
    }

    @Test func aNumberThatIsNotOnOfferIsTakenOut() {
        #expect(TalkReply.shown("{9} That was a long week.", lines: offered, finished: true).text == "That was a long week.")
        // With memory off there are no lines at all.
        #expect(TalkReply.shown("{1} That was a long week.", lines: [], finished: true).text == "That was a long week.")
    }

    @Test func aLineIsWrittenOutOnceHoweverOftenItIsPointedAt() {
        let shown = TalkReply.shown("{1} And again: {1} That one.", lines: offered, finished: true)

        #expect(shown.text.components(separatedBy: monday.quote).count == 2)
    }

    @Test func whileAReplyArrivesHalfANumberIsNotShown() {
        #expect(TalkReply.shown("That was then. {", lines: offered, finished: false).text == "That was then.")
        #expect(TalkReply.shown("That was then. {1", lines: offered, finished: false).text == "That was then.")
        #expect(TalkReply.shown("That was then. {1}", lines: offered, finished: false).text == "That was then.\n\n" + monday.asQuoted)
        // Once the reply is complete, a stray bracket is just what the model wrote.
        #expect(TalkReply.shown("That was then. {", lines: offered, finished: true).text == "That was then. {")
    }

    @Test func aModelCannotPassOffItsOwnWordsAsAnEarlierLine() {
        let shown = TalkReply.shown("> Monday 2 November 2026: \"I never wrote this.\"\n\nToday is different.", lines: offered, finished: true)

        #expect(shown.text == "Monday 2 November 2026: \"I never wrote this.\"\n\nToday is different.")
        #expect(TalkPassage.split(shown.text) == [
            .plain("Monday 2 November 2026: \"I never wrote this.\""),
            .plain("Today is different."),
        ])
    }

    @Test func aSavedReplySplitsIntoPlainWordsAndEarlierLines() {
        let saved = monday.asQuoted + "\n\nToday it's \"I asked him\".\n\nWhat happened in between?"

        #expect(TalkPassage.split(saved) == [
            .earlier(day: "Monday 2 November 2026", quote: "I said yes to everything she asked."),
            .plain("Today it's \"I asked him\"."),
            .plain("What happened in between?"),
        ])
        #expect(TalkPassage.split("Just one paragraph.") == [.plain("Just one paragraph.")])
        // A quote with marks of its own inside it survives.
        let tricky = EarlierLine(number: 3, date: "2026-11-04", label: "Dad", quote: "He said \"about time\": that was all.")
        #expect(TalkPassage.split(tricky.asQuoted) == [.earlier(day: "Wednesday 4 November 2026", quote: "He said \"about time\": that was all.")])
    }

    @Test func aPastReplyGoesBackToTheModelWithNumbersNotWrittenOutLines() {
        let saved = monday.asQuoted + "\n\nToday it's \"I asked him\". What happened in between?"

        #expect(TalkReply.forModel(saved, lines: offered) == "{1}\n\nToday it's \"I asked him\". What happened in between?")
        // The same line under a different number now.
        let renumbered = [EarlierLine(number: 4, date: monday.date, label: monday.label, quote: monday.quote)]
        #expect(TalkReply.forModel(saved, lines: renumbered).hasPrefix("{4}"))
        // No longer on offer (or memory is off): the line is left out.
        #expect(TalkReply.forModel(saved, lines: []) == "Today it's \"I asked him\". What happened in between?")
    }

    @Test func onlyTheModelsOwnWordsCountAsAskingAQuestion() {
        let why = EarlierLine(number: 1, date: "2026-11-02", label: "Meera", quote: "Why did I say yes?")

        #expect(TalkReply.asksAQuestion("What were you hoping he would say?"))
        #expect(!TalkReply.asksAQuestion("Those two don't sit easily together."))
        #expect(!TalkReply.asksAQuestion(why.asQuoted + "\n\nThat was a hard day."))
        #expect(TalkReply.asksAQuestion(why.asQuoted + "\n\nWhat changed?"))
    }

    @Test func aQuestionFromTheWriterIsRecognisedWithOrWithoutItsMark() {
        for asking in ["should I take it? just tell me what you think", "what should i even say to her", "idk. what do you think", "ok\nhow do i even start", "Is it too late"] {
            #expect(TalkReply.writerAsks(asking), "missed: \(asking)")
        }
        for telling in ["he's just a flake, always has been", "yeah. it felt different this time.", "That she'd think I can't handle it.", "whatever. doesn't matter", "thanks, that helps. going to sleep now", ""] {
            #expect(!TalkReply.writerAsks(telling), "caught: \(telling)")
        }
    }

    // MARK: - The care mark

    @Test func theCareMarkIsNeverShown() {
        let shown = TalkReply.shown("[care]\nAre you safe right now? I'm glad you wrote it down.", lines: [], finished: true)

        #expect(shown.text == "Are you safe right now? I'm glad you wrote it down.")
        #expect(shown.flaggedCare)
        #expect(TalkReply.shown("[CARE] Are you safe right now?", lines: [], finished: true) == TalkReply.Shown(text: "Are you safe right now?", flaggedCare: true))
        // Wherever a model puts it, it counts and it is hidden.
        #expect(TalkReply.shown("Are you safe right now?\n\n[care]", lines: [], finished: true) == TalkReply.Shown(text: "Are you safe right now?", flaggedCare: true))
        #expect(!TalkReply.shown("An ordinary reply.", lines: [], finished: true).flaggedCare)
    }

    @Test func whileAReplyArrivesHalfACareMarkIsNotShown() {
        for beginning in ["[", "[c", "[car", "[care"] {
            #expect(TalkReply.shown(beginning, lines: [], finished: false).text == "")
        }
        #expect(TalkReply.shown("[care]", lines: [], finished: false).text == "")
        #expect(TalkReply.shown("[care]\nAre you", lines: [], finished: false).text == "Are you")
        // Something else in brackets is the model's own.
        #expect(TalkReply.shown("[sigh] Long day.", lines: [], finished: false).text == "[sigh] Long day.")
    }

    @Test func askingIfTheyAreSafeIsRecognisedWithoutTheMark() {
        #expect(TalkReply.asksIfSafe("Are you safe right now? I'm glad you wrote it down."))
        #expect(!TalkReply.asksIfSafe("What were you hoping he would say?"))
    }
}

@Suite struct CareNetTests {

    @Test func plainWordsAboutDyingOrHurtingOneselfAreCaught() {
        let danger = [
            "I'm so tired of all of it. Lately I keep thinking everyone would be better off if I just wasn't around.",
            "sometimes i think about just ending it all",
            "I hurt myself again last night. I don't want to talk about why.",
            "kabhi kabhi lagta hai jeena nahi chahti",
            "I want to die.",
            "Some days I  want\nto die",
            "i don\u{2019}t want to be here anymore",
            "They'd be better off without me.",
            "I've been thinking about suicide again",
            "the self-harm is back",
            "I keep thinking about how to kill myself",
            "thought about taking all of it. i want to overdose",
        ]
        for text in danger {
            #expect(CareNet.mayBeInDanger(text), "missed: \(text)")
        }
    }

    @Test func ordinaryWritingIsLeftAlone() {
        let ordinary = [
            "This deadline is killing me. I could have died of embarrassment in standup.",
            "I wanted to die of embarrassment when my screen share showed my tabs.",
            "Slept badly. Too much coffee.",
            "My plant is dying and I feel like a failure.",
            "He said the project is dead. We killed it in the meeting.",
            "I want this week to end.",
            "I want to diet properly this month.",
            "I need to cut myself some slack.",
            "I cut myself shaving and was late.",
            "I'd be better off if I slept more.",
            "Leaving now would be career suicide.",
            "I hurt myself at the gym, the shoulder again.",
            "Nearly died laughing at dinner.",
            "",
        ]
        for text in ordinary {
            #expect(!CareNet.mayBeInDanger(text), "caught: \(text)")
        }
    }

    @Test func everyPhraseIsWrittenTheWayTextIsRead() {
        // The net compares plain lower-case words, so each phrase must already be in that form.
        for phrase in CareNet.phrases + CareNet.figuresOfSpeech {
            #expect(CareNet.words(phrase) == phrase, "not plain: \(phrase)")
        }
        #expect(CareNet.words("Self-harm, again\u{2026} I DON\u{2019}T know") == "self harm again i don't know")
    }
}

@MainActor
@Suite struct TalkCareTests {

    private let hardEntry = TalkEntry(
        id: TalkFixtures.entryID,
        text: "I hurt myself again last night. I don't want to talk about why. I just needed to write it somewhere.",
        date: nil
    )

    @Test func aMessageThatMayMeanDangerShowsTheHelpLineBeforeAnyReply() async {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.hang]))
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        talk.send("some days i just want to die")

        // The reply has not come, and may never come. The line is there and saved.
        #expect(talk.transcript.isWaiting)
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note])
        #expect(talk.transcript.messages.last?.text == Prompts.talkCareLine)
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).map(\.speaker) == [.you, .note])
        talk.turnOff()
    }

    @Test func theModelIsToldToFollowTheDangerRuleAndIsNeverSentTheHelpLine() async throws {
        let sandbox = TalkSandbox()
        try sandbox.writeMadeUpMemory()
        sandbox.settings.memoryEnabled = true
        let provider = FakeProvider([
            .reply(["[care]\n", "Are you safe right now? ", "I'm glad you wrote it down."]),
            .reply(["Thank you for telling me."]),
        ])
        let talk = sandbox.controller(provider)
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        talk.send("Meera again. some days i just want to die")
        await talk.replyTask?.value

        let first = try #require(provider.requests.first)
        #expect(instructions(first).hasSuffix(Prompts.talkDangerNote))
        // That reply is about now: nothing from memory goes with it.
        #expect(!instructions(first).contains("<earlier>"))
        #expect(first.messages == [LLMMessage(role: .user, text: "Meera again. some days i just want to die")])
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note, .diary])
        #expect(talk.transcript.messages.last?.text == "Are you safe right now? I'm glad you wrote it down.")

        talk.send("yes. i'm safe. it was a bad night")
        await talk.replyTask?.value

        let second = try #require(provider.requests.last)
        #expect(!instructions(second).contains("For this reply only"))
        // The model sees its own care reply the way it is asked to write one, and never the app's line.
        #expect(second.messages == [
            LLMMessage(role: .user, text: "Meera again. some days i just want to die"),
            LLMMessage(role: .assistant, text: "[care]\nAre you safe right now? I'm glad you wrote it down."),
            LLMMessage(role: .user, text: "yes. i'm safe. it was a bad night"),
        ])
        #expect(!second.messages.contains { $0.text.contains("14416") })
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note, .diary, .you, .diary])
    }

    @Test func anEntryThatMayMeanDangerShowsTheHelpLineWhenTalkSpeaksFirst() async throws {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([
            .reply(["Are you safe right now? I'm glad you wrote this somewhere."]),
            .reply(["Okay. I'm here."]),
        ])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: hardEntry)
        await talk.replyTask?.value

        let first = try #require(provider.requests.first)
        #expect(instructions(first).hasSuffix(Prompts.talkDangerNote))
        #expect(first.messages == [LLMMessage(role: .user, text: Prompts.talkOpener)])
        #expect(talk.transcript.messages.map(\.speaker) == [.note, .diary])

        // The line is shown once for the entry, not again with every message.
        talk.send("i'm ok now. just tired")
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.note, .diary, .you, .diary])
        #expect(!instructions(provider.requests.last).contains("For this reply only"))
    }

    @Test func ifNoReplyComesTheHelpLineStaysAndTryingAgainIsStillAboutDanger() async throws {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.fail(.offline), .reply(["Are you safe right now? I'm glad you wrote this."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: hardEntry)
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.note])
        #expect(talk.transcript.canRetry)

        // Closing and opening talk again speaks first again, without a second line.
        talk.retry()
        await talk.replyTask?.value

        #expect(provider.requests.count == 2)
        #expect(instructions(provider.requests.last).hasSuffix(Prompts.talkDangerNote))
        #expect(talk.transcript.messages.map(\.speaker) == [.note, .diary])
    }

    @Test func aConversationThatOnlyHoldsTheHelpLineStillLetsTalkSpeakFirst() async {
        let sandbox = TalkSandbox()
        sandbox.store.save([TalkMessage(speaker: .note, text: Prompts.talkCareLine, date: Date(timeIntervalSince1970: 1_793_995_000))], entryID: TalkFixtures.entryID)
        let provider = FakeProvider([.reply(["Are you safe right now? I'm glad you wrote this."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: hardEntry)
        await talk.replyTask?.value

        #expect(provider.requests.count == 1)
        #expect(talk.transcript.messages.map(\.speaker) == [.note, .diary])
    }

    @Test func whenTheModelSeesDangerTheNetMissedTheHelpLineIsShownWithItsReply() async throws {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([
            .reply(["[care]\nAre you safe right now? I'm glad you wrote it down."]),
            .reply(["[care]\nI'm staying right here with you."]),
        ])
        let talk = sandbox.controller(provider)
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        talk.send("i can't see the point of any of it lately")
        await talk.replyTask?.value

        // The net did not catch this wording, so the model was told nothing extra.
        #expect(!instructions(provider.requests.first).contains("For this reply only"))
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note, .diary])
        #expect(talk.transcript.messages.last?.text == "Are you safe right now? I'm glad you wrote it down.")
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).map(\.speaker) == [.you, .note, .diary])

        // While it stays with them, the line is not repeated under every reply.
        talk.send("no")
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note, .diary, .you, .diary])
        #expect(talk.transcript.messages.last?.text == "I'm staying right here with you.")
    }

    @Test func askingIfTheyAreSafeShowsTheHelpLineEvenWithoutTheMark() async {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.reply(["Are you safe right now? I'm glad you wrote it down."])]))
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        talk.send("i can't see the point of any of it lately")
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.you, .note, .diary])
    }

    @Test func anOrdinaryConversationNeverShowsTheHelpLine() async {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.reply(["You said yes and then felt sick."]), .reply(["That is a lot to carry."])]))

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value
        talk.send("This deadline is killing me, honestly.")
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.diary, .you, .diary])
    }
}

@MainActor
@Suite struct TalkQuestionTests {

    private func talkAfterAQuestion(_ provider: FakeProvider) -> (TalkSandbox, TalkController) {
        let sandbox = TalkSandbox()
        // The saved conversation ends with a reply that asks a question.
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.entryID)
        let talk = sandbox.controller(provider)
        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        return (sandbox, talk)
    }

    @Test func afterAnAnsweredQuestionTheNextReplyIsToldNotToAskAnother() async throws {
        let provider = FakeProvider([.reply(["You already knew you didn't want to."]), .reply(["Sleep well."])])
        let (sandbox, talk) = talkAfterAQuestion(provider)

        talk.send("That I already knew I didn't want to do it.")
        await talk.replyTask?.value

        let first = try #require(provider.requests.first)
        #expect(first.system == Prompts.talkSystem(entryText: TalkFixtures.entry.text, entryDate: TalkFixtures.entry.date, turn: .noQuestion))
        #expect(instructions(first).hasSuffix(Prompts.talkNoQuestionNote))

        // That reply asked nothing, so the one after it is free again.
        talk.send("yeah")
        await talk.replyTask?.value

        #expect(provider.requests.last?.system == Prompts.talkSystem(entryText: TalkFixtures.entry.text, entryDate: TalkFixtures.entry.date))
        _ = sandbox
    }

    @Test func aQuestionFromThemIsAnsweredNotSaidBack() async throws {
        let provider = FakeProvider([.reply(["I can't choose that for you."])])
        let (sandbox, talk) = talkAfterAQuestion(provider)

        talk.send("what do you think I should do")
        await talk.replyTask?.value

        #expect(!instructions(provider.requests.first).contains("For this reply only"))
        _ = sandbox
    }

    @Test func theTurnIsWorkedOutFromTheConversationAlone() {
        let at = Date(timeIntervalSince1970: 1_793_995_000)
        func you(_ text: String) -> TalkMessage { TalkMessage(speaker: .you, text: text, date: at) }
        func diary(_ text: String) -> TalkMessage { TalkMessage(speaker: .diary, text: text, date: at) }
        let helpLine = TalkMessage(speaker: .note, text: Prompts.talkCareLine, date: at)

        // Talk speaks first, or the first message: nothing to add.
        #expect(TalkController.turn(for: []) == .ordinary)
        #expect(TalkController.turn(for: [you("long day")]) == .ordinary)
        // A question, then an answer.
        #expect(TalkController.turn(for: [diary("What happened?"), you("he left")]) == .noQuestion)
        // No question was asked.
        #expect(TalkController.turn(for: [diary("That is a hard place to be."), you("yeah")]) == .ordinary)
        // A question inside an earlier line is theirs, not the reply's.
        #expect(TalkController.turn(for: [diary("> Monday 2 November 2026: \"Why did I say yes?\"\n\nThat was a hard day."), you("it was")]) == .ordinary)
        // Danger comes before everything, and covers every message still waiting for a reply.
        #expect(TalkController.turn(for: [diary("What happened?"), you("i want to die")]) == .danger)
        #expect(TalkController.turn(for: [you("i want to die"), helpLine, you("hello?")]) == .danger)
        #expect(TalkController.turn(for: [helpLine]) == .danger)
        // Once it has been answered, the danger rule is the model's to keep, and the app does
        // not tell it to stop asking: it may need to.
        #expect(TalkController.turn(for: [you("i want to die"), helpLine, diary("Are you safe right now?"), you("not really")]) == .ordinary)
        #expect(TalkController.turn(for: [you("i want to die"), helpLine, diary("Are you safe right now?"), you("yes"), diary("What helped?"), you("my sister called")]) == .noQuestion)
    }
}

@MainActor
@Suite struct TalkEarlierLineTests {

    private let entry = TalkEntry(
        id: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
        text: "Meera wants an answer today and I still don't have one.",
        date: MemoryWeek.day(10)
    )

    @Test func theAppWritesTheEarlierLineTheModelPointsAt() async throws {
        let sandbox = TalkSandbox()
        try sandbox.writeMadeUpMemory()
        sandbox.settings.memoryEnabled = true
        let context = ContextBuilder.build(
            entry: entry, recentMessages: [],
            memory: sandbox.memoryStore.loadSnapshot(), digests: sandbox.memoryStore.loadAllDigests()
        )
        let line = try #require(Prompts.earlierLines(from: context).dropFirst().first)
        let provider = FakeProvider([
            .reply(["{\(line.number)", "} Today it's \"still don't have one\". ", "What is in the way?"]),
            .reply(["That makes sense."]),
        ])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: entry)
        await talk.replyTask?.value

        // The words and the day come from memory, not from the model.
        let expected = line.asQuoted + "\n\nToday it's \"still don't have one\". What is in the way?"
        #expect(talk.transcript.messages.map(\.text) == [expected])
        #expect(sandbox.store.load(entryID: entry.id).map(\.text) == [expected])
        #expect(expected.contains(Prompts.longDay(line.date)))

        // Next time, the model sees the number it used, not a written-out line.
        talk.send("i don't want to let her down")
        await talk.replyTask?.value

        let second = try #require(provider.requests.last)
        #expect(second.messages.count == 3)
        #expect(second.messages[1].role == .assistant)
        #expect(second.messages[1].text.hasPrefix("{"))
        #expect(second.messages[1].text.hasSuffix("}\n\nToday it's \"still don't have one\". What is in the way?"))
        #expect(!second.messages[1].text.contains(line.quote))
    }

    @Test func withMemoryOffANumberPointsAtNothing() async {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.reply(["{1} Today it's \"still don't have one\"."])]))

        talk.toggle()
        talk.show(entry: entry)
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.text) == ["Today it's \"still don't have one\"."])
    }
}

@MainActor
@Suite struct TalkColumnOrderTests {
    private let at = Date(timeIntervalSince1970: 1_793_995_000)
    private func you(_ text: String) -> TalkMessage { TalkMessage(speaker: .you, text: text, date: at) }
    private func diary(_ text: String) -> TalkMessage { TalkMessage(speaker: .diary, text: text, date: at) }
    private var helpLine: TalkMessage { TalkMessage(speaker: .note, text: Prompts.talkCareLine, date: at) }

    @Test func theHelpLineIsDrawnUnderTheReplyItCameWith() {
        let order = TalkColumn.drawingOrder([you("a"), helpLine, diary("b"), you("c"), diary("d")], replyOnItsWay: false)

        #expect(order.settled.map(\.speaker) == [.you, .diary, .note, .you, .diary])
        #expect(order.underTheReply == nil)
    }

    @Test func whileItsReplyIsOnTheWayTheHelpLineWaitsBelowIt() {
        let order = TalkColumn.drawingOrder([you("a"), helpLine], replyOnItsWay: true)

        #expect(order.settled.map(\.speaker) == [.you])
        #expect(order.underTheReply?.speaker == .note)
    }

    @Test func aHelpLineWithNoReplyStaysWhereItIs() {
        // The reply failed and they wrote again.
        let order = TalkColumn.drawingOrder([you("a"), helpLine, you("b")], replyOnItsWay: false)

        #expect(order.settled.map(\.speaker) == [.you, .note, .you])
        #expect(TalkColumn.drawingOrder([helpLine], replyOnItsWay: false).settled.map(\.speaker) == [.note])
    }

    @Test func anOrdinaryConversationIsDrawnAsSaved() {
        let saved = TalkFixtures.conversation()

        #expect(TalkColumn.drawingOrder(saved, replyOnItsWay: true).settled == saved)
        #expect(TalkColumn.drawingOrder(saved, replyOnItsWay: true).underTheReply == nil)
    }
}
