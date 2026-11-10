//
//  SettingsSnapshotTests.swift
//  freewriteTests
//
//  Draws the Settings window off screen and attaches a picture of it to the
//  test results, so its look can be checked without clicking through the app.
//  It uses throwaway settings, so the real preferences and key are untouched.
//

import XCTest
import SwiftUI
@testable import freewrite

final class SettingsSnapshotTests: XCTestCase {

    @MainActor
    func testSettingsDrawsWithAIOffInLightMode() throws {
        try snapshot(named: "settings-light-ai-off", dark: false) { _, _ in }
    }

    @MainActor
    func testSettingsDrawsWithAIAndMemoryOnInDarkMode() throws {
        try snapshot(named: "settings-dark-ai-on", dark: true) { settings, memory in
            settings.aiEnabled = true
            settings.saveAPIKey("made-up-key-for-tests")
            settings.memoryEnabled = true
            memory.summary = MemorySummary(thoughts: 14, digestedEntries: 9, waitingEntries: 1)
            memory.summary.lastTidy = "Tidied on Monday 9 November 2026: merged 1, retired 2, 1 pattern across weeks."
        }
    }

    @MainActor
    func testSettingsShowsAMemoryProblemAsOnePlainLine() throws {
        try snapshot(named: "settings-light-memory-problem", dark: false) { settings, memory in
            settings.aiEnabled = true
            settings.saveAPIKey("made-up-key-for-tests")
            settings.memoryEnabled = true
            memory.summary = MemorySummary(thoughts: 3, digestedEntries: 2, waitingEntries: 4, problem: LLMError.offline.userMessage)
        }
    }

    @MainActor
    private func snapshot(named name: String, dark: Bool, configure: (AISettings, MemoryStatus) -> Void) throws {
        let suiteName = "deardiary.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychain = Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString)", account: "test")
        defer {
            keychain.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(dark ? "dark" : "light", forKey: "colorScheme")
        let settings = AISettings(defaults: defaults, keychain: keychain)
        let memoryStatus = MemoryStatus()
        configure(settings, memoryStatus)

        let view = SettingsView(settings: settings, memoryStatus: memoryStatus, memoryActions: .none)
            .defaultAppStorage(defaults)

        attach(try renderOffscreen(view, dark: dark), named: name)
    }
}
