//
//  PageSnapshotTests.swift
//  freewriteTests
//
//  Draws the whole writing window off screen, once with AI off and once with
//  AI on and a (made-up) key saved, and attaches both pictures to the test
//  results. With AI off the bottom bar must be freewrite's; with AI on, "Talk"
//  takes the place of "Chat". Talk is never switched on here, so nothing is sent.
//

import XCTest
import SwiftUI
@testable import freewrite

final class PageSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 600)

    @MainActor
    func testPageWithAIOffLooksLikeFreewrite() throws {
        // Under test the shared settings are a throwaway copy, and AI starts off.
        XCTAssertFalse(AISettings.shared.aiEnabled)

        attach(try renderOffscreen(ContentView(), size: windowSize, dark: false), named: "page-ai-off")
    }

    @MainActor
    func testPageWithAIOnShowsTheTalkWord() throws {
        let settings = AISettings.shared
        settings.aiEnabled = true
        settings.saveAPIKey("made-up-key-for-tests")
        defer {
            settings.aiEnabled = false
            settings.removeAPIKey()
        }

        attach(try renderOffscreen(ContentView(), size: windowSize, dark: false), named: "page-ai-on")
    }
}
