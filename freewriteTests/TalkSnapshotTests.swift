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
