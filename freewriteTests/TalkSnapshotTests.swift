//
//  TalkSnapshotTests.swift
//  freewriteTests
//
//  Draws the talk column off screen in its main states and attaches the
//  pictures to the test results, so its look can be checked without a real
//  conversation. Everything shown is made up.
//

import XCTest
import SwiftUI
@testable import freewrite

final class TalkSnapshotTests: XCTestCase {

    private let columnSize = CGSize(width: 340, height: 600)

    @MainActor
    private func column(_ talk: TalkController, dark: Bool) -> some View {
        TalkColumn(
            talk: talk,
            transcript: talk.transcript,
            style: TalkStyle(fontName: "Lato-Regular", pageFontSize: 18, isLight: !dark)
        )
    }

    @MainActor
    func testConversationInLightMode() async throws {
        let sandbox = TalkSandbox()
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.entryID)
        let talk = sandbox.controller(FakeProvider())
        talk.toggle()
        talk.show(entry: TalkFixtures.entry)

        attach(try renderOffscreen(column(talk, dark: false), size: columnSize, dark: false), named: "talk-light-conversation")
        XCTAssertEqual(talk.transcript.messages.count, 3)
    }

    @MainActor
    func testWaitingForAReplyInDarkMode() async throws {
        let sandbox = TalkSandbox()
        sandbox.store.save(TalkFixtures.conversation(), entryID: TalkFixtures.entryID)
        let talk = sandbox.controller(FakeProvider([.hang]))
        talk.toggle()
        talk.show(entry: TalkFixtures.entry)
        talk.send("That I already knew I didn't want to do it.")

        attach(try renderOffscreen(column(talk, dark: true), size: columnSize, dark: true), named: "talk-dark-waiting")
        XCTAssertTrue(talk.transcript.isWaiting)
        talk.turnOff()
    }

    @MainActor
    func testDeclinedReplyShowsSupportOptions() async throws {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.fail(.refused)]))
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("I don't know how to say this.")
        await talk.replyTask?.value

        attach(try renderOffscreen(column(talk, dark: false), size: columnSize, dark: false), named: "talk-light-declined")
        XCTAssertEqual(talk.transcript.notice, Prompts.talkDeclinedNotice)
    }

    /// A reply that brings up an earlier day. The grey line beside the rule, and its day,
    /// are written by the app from memory, not by the model.
    @MainActor
    func testAnEarlierLineInLightMode() async throws {
        let sandbox = TalkSandbox()
        let earlier = EarlierLine(
            number: 1, date: "2026-11-02", label: "Meera",
            quote: "I said yes to everything she asked and then felt sick about it for the rest of the day."
        )
        let start = Date(timeIntervalSince1970: 1_793_995_000)
        sandbox.store.save([
            TalkMessage(speaker: .diary, text: earlier.asQuoted + "\n\nToday it's \"I needed to think about it\", and you \"slept fine\". What was different about how you answered her this time?", date: start),
            TalkMessage(speaker: .you, text: "yeah. it felt different this time.", date: start.addingTimeInterval(40)),
            TalkMessage(speaker: .diary, text: "It felt different because you told her you \"needed to think about it\", and nothing fell apart.", date: start.addingTimeInterval(55)),
        ], entryID: TalkFixtures.entryID)
        let talk = sandbox.controller(FakeProvider())
        talk.toggle()
        talk.show(entry: TalkFixtures.entry)

        attach(try renderOffscreen(column(talk, dark: false), size: columnSize, dark: false), named: "talk-light-earlier-line")
        attach(try renderOffscreen(column(talk, dark: true), size: columnSize, dark: true), named: "talk-dark-earlier-line")
        XCTAssertEqual(TalkPassage.split(talk.transcript.messages[0].text).first, .earlier(day: "Monday 2 November 2026", quote: earlier.quote))
    }

    /// The app's own help line, under the reply it came with.
    @MainActor
    func testTheHelpLineInDarkAndLightMode() async throws {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.reply(["[care]\nAre you safe right now? I'm glad you wrote this down somewhere."])]))
        talk.toggle()
        talk.show(entry: TalkEntry(id: TalkFixtures.entryID, text: "I hurt myself again last night. I don't want to talk about why. I just needed to write it somewhere.", date: nil))
        await talk.replyTask?.value

        attach(try renderOffscreen(column(talk, dark: true), size: columnSize, dark: true), named: "talk-dark-help-line")
        attach(try renderOffscreen(column(talk, dark: false), size: columnSize, dark: false), named: "talk-light-help-line")
        XCTAssertEqual(talk.transcript.messages.map(\.speaker), [.note, .diary])
        XCTAssertEqual(talk.transcript.messages.first?.text, Prompts.talkCareLine)
    }

    /// The help line is on the page before any reply has come.
    @MainActor
    func testTheHelpLineWhileWaitingForAReply() async throws {
        let sandbox = TalkSandbox()
        let talk = sandbox.controller(FakeProvider([.hang]))
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)
        talk.send("some days i just want to die")

        attach(try renderOffscreen(column(talk, dark: true), size: columnSize, dark: true), named: "talk-dark-help-line-waiting")
        XCTAssertTrue(talk.transcript.isWaiting)
        XCTAssertEqual(talk.transcript.messages.last?.speaker, .note)
        talk.turnOff()
    }

    @MainActor
    func testEmptyColumnWaitsForYou() async throws {
        let sandbox = TalkSandbox()
        let provider = FakeProvider()
        let talk = sandbox.controller(provider)
        talk.toggle()
        talk.show(entry: TalkFixtures.emptyEntry)

        attach(try renderOffscreen(column(talk, dark: false), size: columnSize, dark: false), named: "talk-light-empty")
        XCTAssertTrue(provider.requests.isEmpty)
    }
}
