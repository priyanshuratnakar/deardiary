//
//  TalkControllerTests.swift
//  freewriteTests
//
//  Checks how talk mode behaves, using a pretend AI and made-up entries:
//  when it speaks, what it sends, what it saves, and that it sends nothing
//  while it is off.
//

import AppKit
import Foundation
import Testing
@testable import freewrite

@MainActor
@Suite struct TalkControllerTests {

    // MARK: - Speaking first

    @Test func speaksFirstWhenSwitchedOnWithWritingOnThePage() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.reply(["You said yes ", "to everything."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value

        #expect(talk.isOn)
        #expect(provider.requests.count == 1)
        #expect(talk.transcript.messages.map(\.speaker) == [.diary])
        #expect(talk.transcript.messages.first?.text == "You said yes to everything.")
        #expect(talk.transcript.isBusy == false)

        // The unseen opening line stands in for the user, and the entry is in the instructions.
        let request = provider.requests[0]
        #expect(request.messages == [LLMMessage(role: .user, text: Prompts.talkOpener)])
        #expect(request.system?.contains(TalkFixtures.entryText) == true)

        // Saved next to the journal.
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID) == talk.transcript.messages)
    }

    @Test func waitsForYouWhenThePageIsEmpty() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        await talk.replyTask?.value

        #expect(talk.isOn)
        #expect(provider.requests.isEmpty)
        #expect(talk.transcript.messages.isEmpty)
    }

    @Test func doesNotSpeakAgainWhenTheEntryAlreadyHasAConversation() async {
        let sandbox = TalkSandbox()
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.entryID)
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value

        #expect(provider.requests.isEmpty)
        #expect(talk.transcript.messages == TalkFixtures.conversation())
    }

    @Test func onlySpeaksFirstAtTheMomentItIsSwitchedOn() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        // Later the column shows a different entry that has writing but no conversation.
        let other = TalkEntry(id: TalkFixtures.otherEntryID, text: "Something written on another day.", date: nil)
        talk.show(entry: other)
        await talk.replyTask?.value

        #expect(provider.requests.isEmpty)
        #expect(talk.transcript.messages.isEmpty)
    }

    // MARK: - Talking

    @Test func sendingAMessageSavesBothSides() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.reply(["First reply."]), .reply(["Second ", "reply."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value

        talk.send("  That she'd think I can't handle it.  ")
        await talk.replyTask?.value

        #expect(talk.transcript.messages.map(\.speaker) == [.diary, .you, .diary])
        #expect(talk.transcript.messages.map(\.text) == [
            "First reply.",
            "That she'd think I can't handle it.",
            "Second reply.",
        ])
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID) == talk.transcript.messages)

        // The second request carries the whole conversation, taking turns, starting with the user.
        #expect(provider.requests[1].messages == [
            LLMMessage(role: .user, text: Prompts.talkOpener),
            LLMMessage(role: .assistant, text: "First reply."),
            LLMMessage(role: .user, text: "That she'd think I can't handle it."),
        ])
    }

    @Test func usesTheTalkModelFromSettings() async {
        let sandbox = TalkSandbox()
        sandbox.settings.talkModel = "the-model-i-typed"
        let provider = FakeProvider([.reply(["Hello."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value

        #expect(provider.requests.first?.model == "the-model-i-typed")
        #expect(provider.requests.first?.maxTokens == AILimits.talkMaxTokens)
        #expect(provider.requests.first?.retryIfDeclined == true)
    }

    @Test func everyRequestCarriesThePageAsItReadsNow() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.reply(["Reply."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.entryTextChanged("A line I wrote after switching talk on.")
        talk.send("What do you make of that?")
        await talk.replyTask?.value

        #expect(provider.requests.count == 1)
        #expect(provider.requests[0].system?.contains("A line I wrote after switching talk on.") == true)
    }

    @Test func emptyMessagesAreNotSent() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("   \n ")
        await talk.replyTask?.value

        #expect(provider.requests.isEmpty)
        #expect(talk.transcript.messages.isEmpty)
    }

    // MARK: - Off means off

    @Test func nothingIsSentWhileTalkIsOff() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)

        talk.show(entry: TalkFixtures.entry)
        talk.send("Hello?")
        talk.retry()
        await talk.replyTask?.value

        #expect(talk.isOn == false)
        #expect(provider.requests.isEmpty)
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).isEmpty)
    }

    @Test func switchingOffCancelsTheReplyAndDropsWhatHadArrived() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.hang])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        #expect(talk.transcript.isWaiting)
        await waitUntil { provider.requests.count == 1 }
        #expect(provider.requests.count == 1)

        talk.toggle()

        #expect(talk.isOn == false)
        #expect(talk.transcript.isBusy == false)
        #expect(talk.replyTask == nil)
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).isEmpty)

        // And nothing more is sent afterwards.
        talk.send("Still there?")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(provider.requests.count == 1)
    }

    @Test func switchingOffStraightAwayMeansNothingIsEverSent() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.reply(["Too late."])])
        let talk = sandbox.controller(provider)

        // On and off again before the request has had a chance to start.
        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        talk.toggle()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(provider.requests.isEmpty)
        #expect(talk.transcript.messages.isEmpty)
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).isEmpty)
    }

    @Test func talkIsNotOfferedWithoutAKeyOrWithAIOff() {
        let noKey = TalkSandbox(aiOn: true, hasKey: false)
        let talkWithoutKey = noKey.controller(FakeProvider())
        talkWithoutKey.toggle()
        #expect(talkWithoutKey.isAvailable == false)
        #expect(talkWithoutKey.isOn == false)

        let aiOff = TalkSandbox(aiOn: false, hasKey: true)
        let talkWithAIOff = aiOff.controller(FakeProvider())
        talkWithAIOff.toggle()
        #expect(talkWithAIOff.isAvailable == false)
        #expect(talkWithAIOff.isOn == false)
    }

    @Test func turningAIOffInSettingsClosesTalk() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.hang])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        #expect(talk.isOn)

        sandbox.settings.aiEnabled = false

        #expect(talk.isAvailable == false)
        #expect(talk.isOn == false)
        #expect(talk.transcript.isBusy == false)

        sandbox.settings.aiEnabled = true
        #expect(talk.isAvailable)
        #expect(talk.isOn == false)
    }

    // MARK: - Following the page

    @Test func switchingEntriesShowsThatEntrysConversationAndSendsNothing() async {
        let sandbox = TalkSandbox()
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.otherEntryID)
        let provider = FakeProvider([.reply(["About the first entry."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value
        #expect(provider.requests.count == 1)

        talk.show(entry: TalkEntry(id: TalkFixtures.otherEntryID, text: "Another day.", date: nil))
        await talk.replyTask?.value

        #expect(provider.requests.count == 1)
        #expect(talk.transcript.messages == TalkFixtures.conversation())

        // Each entry keeps its own file.
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).map(\.text) == ["About the first entry."])
    }

    @Test func deletingAnEntryDeletesItsConversation() async {
        let sandbox = TalkSandbox()
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.entryID)
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.otherEntryID)
        let talk = sandbox.controller(FakeProvider())

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        talk.entryDeleted(TalkFixtures.entryID)

        #expect(talk.transcript.messages.isEmpty)
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).isEmpty)
        #expect(sandbox.store.load(entryID: TalkFixtures.otherEntryID) == TalkFixtures.conversation())
    }

    // MARK: - When things go wrong

    @Test func aDeclinedReplyShowsTheSupportOptionsAndKeepsYourMessage() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.replyThenFail(["I can't"], .refused), .reply(["I'm here."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("I don't know how to say this.")
        await talk.replyTask?.value

        #expect(talk.transcript.notice == Prompts.talkDeclinedNotice)
        #expect(talk.transcript.notice?.contains("14416") == true)
        #expect(talk.transcript.canRetry)
        // The half-written reply is thrown away; what you wrote is kept.
        #expect(talk.transcript.replyInProgress == nil)
        #expect(talk.transcript.messages.map(\.speaker) == [.you])
        #expect(sandbox.store.load(entryID: TalkFixtures.entryID).map(\.text) == ["I don't know how to say this."])

        talk.retry()
        await talk.replyTask?.value

        #expect(talk.transcript.notice == nil)
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .diary])
        #expect(provider.requests.count == 2)
    }

    @Test func aFailureShowsOnePlainSentence() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.fail(.offline)])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        await talk.replyTask?.value

        #expect(talk.transcript.notice == LLMError.offline.userMessage)
        #expect(talk.transcript.messages.isEmpty)
        #expect(talk.transcript.isBusy == false)
    }

    @Test func afterAFailureTheNextMessageStillTakesTurnsProperly() async {
        let sandbox = TalkSandbox()
        let provider = FakeProvider([.fail(.overloaded), .reply(["Now I'm here."])])
        let talk = sandbox.controller(provider)

        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("First try.")
        await talk.replyTask?.value
        talk.send("Second try.")
        await talk.replyTask?.value

        // Two of your messages in a row are sent as one turn.
        #expect(provider.requests[1].messages == [LLMMessage(role: .user, text: "First try.\n\nSecond try.")])
        #expect(talk.transcript.messages.map(\.speaker) == [.you, .you, .diary])
    }

    // MARK: - Small pieces

    @Test func readsTheDateOutOfAnEntryFilename() throws {
        let date = try #require(TalkEntry.date(fromFilename: "[6910BBDE-75FC-415C-ABB9-C76644B037B2]-[2026-02-20-08-01-04].md"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        #expect(parts.year == 2026)
        #expect(parts.month == 2)
        #expect(parts.day == 20)
        #expect(parts.hour == 8)
        #expect(parts.minute == 1)
        #expect(parts.second == 4)

        #expect(TalkEntry.date(fromFilename: "notes.md") == nil)
        #expect(TalkEntry.date(fromFilename: nil) == nil)
    }
}

@Suite struct TalkPromptTests {

    @Test func theVoiceCarriesEverythingThePRDAsksFor() {
        let voice = Prompts.talkVoice

        // A close friend who read every word. Short plain prose, at most one question.
        #expect(voice.contains("close friend who read every word"))
        #expect(voice.contains("plain prose"))
        #expect(voice.contains("At most one question in a reply."))
        // Uses their own words, and does not open with a stock phrase.
        #expect(voice.contains("Use their own words, in double quote marks"))
        #expect(voice.contains("Never begin with \"It sounds like\""))
        // Does not flatter, agree to be kind, diagnose, label, or judge people it has not met.
        #expect(voice.contains("do not flatter"))
        #expect(voice.contains("Do not agree just to be kind"))
        #expect(voice.contains("Do not diagnose or label"))
        #expect(voice.contains("Do not judge the people they mention"))
        // Points toward real people; is honest about not being a therapist.
        #expect(voice.contains("real people in their life"))
        #expect(voice.contains("not a therapist"))
        // Only states what it can tie to the entry.
        #expect(voice.contains("You cannot see their other entries."))
        // Safety: drop everything else, ask if safe, mark the reply, leave the numbers to the app.
        #expect(voice.contains("drop everything above"))
        #expect(voice.contains("whether they are safe right now"))
        #expect(voice.contains("Start your reply with [care] on a line of its own."))
        #expect(voice.contains("do not list numbers yourself"))
        #expect(voice.contains("Ordinary figures of speech are not danger"))
    }

    @Test func theExamplesKeepTheRulesTheyTeach() {
        // Models copy examples more closely than rules, so the examples must not break one.
        let replies = Prompts.talkManner
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("Reply: ") }
            .map { String($0.dropFirst("Reply: ".count)) }
        #expect(replies.count == 6)

        let stockOpeners = ["It sounds like", "It seems", "I hear", "I understand", "I notice", "I'm here", "That must be"]
        for reply in replies {
            #expect(!stockOpeners.contains(where: { reply.hasPrefix($0) }))
            #expect(reply.filter { $0 == "?" }.count <= 1)
            #expect(!reply.lowercased().contains("tell me more"))
            // Each one uses the writer's own words, in quote marks.
            #expect(reply.contains("\""))
        }
        // Some replies ask nothing at all.
        #expect(replies.contains { !$0.contains("?") })
    }

    @Test func theHelpLineIsTheAppsOwnAndNamesWhereToTurn() {
        #expect(Prompts.talkCareLine.contains("someone you trust"))
        #expect(Prompts.talkCareLine.contains("Tele-MANAS on 14416"))
        #expect(Prompts.talkCareLine.contains("local emergency number"))
        // The model is never given the numbers to repeat.
        #expect(!Prompts.talkVoice.contains("14416"))
        #expect(!Prompts.talkVoiceWithMemory.contains("14416"))
    }

    @Test func aNoteForOneReplyGoesLastSoItIsTheFreshestThingRead() {
        let ordinary = Prompts.talkSystem(entryText: "Couldn't sleep again.", entryDate: nil)
        let noQuestion = Prompts.talkSystem(entryText: "Couldn't sleep again.", entryDate: nil, turn: .noQuestion)
        let danger = Prompts.talkSystem(entryText: "Couldn't sleep again.", entryDate: nil, turn: .danger)

        #expect(!ordinary.contains("For this reply only"))
        #expect(noQuestion == ordinary + "\n\n" + Prompts.talkNoQuestionNote)
        #expect(danger == ordinary + "\n\n" + Prompts.talkDangerNote)
        #expect(Prompts.talkNoQuestionNote.contains("Do not ask another question now."))
        #expect(Prompts.talkDangerNote.contains("If they may be in danger"))
    }

    @Test func theEntryIsHandedOverBetweenClearMarkers() {
        let date = Date(timeIntervalSince1970: 1_793_990_000)
        let system = Prompts.talkSystem(entryText: "\n\n  Couldn't sleep again.  \n", entryDate: date)

        #expect(system.hasPrefix(Prompts.talkVoice))
        #expect(system.contains("<entry>\nCouldn't sleep again.\n</entry>"))
        #expect(system.contains("It was started on "))
        #expect(system.contains("2026"))
    }

    @Test func anEmptyPageIsDescribedAsEmpty() {
        let system = Prompts.talkSystem(entryText: " \n\n ", entryDate: nil)

        #expect(system.contains("The page is empty right now."))
        #expect(!system.contains("<entry>"))
    }

    @Test func theDeclinedMessageNamesTheSupportOptions() {
        #expect(Prompts.talkDeclinedNotice.contains("someone you trust"))
        #expect(Prompts.talkDeclinedNotice.contains("Tele-MANAS on 14416"))
        #expect(Prompts.talkDeclinedNotice.contains("local emergency services"))
    }
}

@MainActor
@Suite(.serialized) struct BackspaceLockScopeTests {

    private func deleteKey() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        )
    }

    @Test func theLockAppliesByDefaultSoThePageBehavesAsBefore() throws {
        BackspaceLockScope.talkInputFocused = false
        let event = try #require(deleteKey())

        #expect(BackspaceLockScope.applies(to: event))
    }

    @Test func theLockDoesNotApplyWhileTypingInTheTalkBox() throws {
        BackspaceLockScope.talkInputFocused = true
        defer { BackspaceLockScope.talkInputFocused = false }
        let event = try #require(deleteKey())

        #expect(BackspaceLockScope.applies(to: event) == false)
    }
}
