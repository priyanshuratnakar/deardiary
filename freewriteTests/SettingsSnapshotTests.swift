//
//  SettingsSnapshotTests.swift
//  freewriteTests
//
//  Draws the Settings window off screen and attaches pictures of it to the
//  test results, so its look can be checked without clicking through the app:
//  AI off, each kind of service, the states in between (no key yet, Ollama not
//  running), and each step of bringing entries across from freewrite. It uses
//  throwaway settings and a fixed model list, so the real preferences and keys
//  are untouched and no service is asked.
//

import XCTest
import SwiftUI
@testable import freewrite

final class SettingsSnapshotTests: XCTestCase {

    private static let claudeModels = [
        AIModelChoice(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
        AIModelChoice(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        AIModelChoice(id: "claude-haiku-5-5", name: "Claude Haiku 5.5"),
    ]

    private static let localModels = [
        AIModelChoice(id: "gemma-test:12b", name: "gemma-test:12b", detail: "12.2B"),
        AIModelChoice(id: "llama-test", name: "llama-test", detail: "3.2B"),
        AIModelChoice(id: "qwen-test:8b", name: "qwen-test:8b", detail: "8.2B"),
    ]

    @MainActor
    func testSettingsDrawsWithAIOffInLightMode() throws {
        try snapshot(named: "settings-light-ai-off", dark: false) { _ in }
    }

    @MainActor
    func testSettingsDrawsWithClaudeAndMemoryOnInDarkMode() throws {
        try snapshot(named: "settings-dark-ai-on", dark: true) { parts in
            parts.settings.aiEnabled = true
            parts.settings.saveAPIKey("made-up-key-for-tests")
            parts.settings.memoryEnabled = true
            parts.versions.enabled = true
            parts.catalog.show(.loaded(Self.claudeModels))
            parts.memory.summary = MemorySummary(thoughts: 14, digestedEntries: 9, waitingEntries: 1)
            parts.memory.summary.lastTidy = "Tidied on Monday 9 November 2026: merged 1, retired 2, 1 pattern across weeks."
        }
    }

    @MainActor
    func testSettingsShowsAMemoryProblemAsOnePlainLine() throws {
        try snapshot(named: "settings-light-memory-problem", dark: false) { parts in
            parts.settings.aiEnabled = true
            parts.settings.saveAPIKey("made-up-key-for-tests")
            parts.settings.memoryEnabled = true
            parts.catalog.show(.loaded(Self.claudeModels))
            parts.memory.summary = MemorySummary(thoughts: 3, digestedEntries: 2, waitingEntries: 4, problem: LLMError.offline.userMessage)
        }
    }

    @MainActor
    func testSettingsWithAModelOnThisMac() throws {
        try snapshot(named: "settings-light-on-this-mac", dark: false) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .local
            parts.settings.talkModel = "llama-test"
            parts.settings.digestModel = "qwen-test:8b"
            parts.settings.memoryEnabled = true
            parts.catalog.show(.loaded(Self.localModels))
            parts.memory.summary = MemorySummary(thoughts: 14, digestedEntries: 9, waitingEntries: 0)
        }
        XCTAssertEqual(SettingsView.description(of: .local), "A free open model that runs on this Mac through Ollama. Nothing you write leaves this Mac.")
    }

    @MainActor
    func testSettingsWhenOllamaIsNotRunning() throws {
        try snapshot(named: "settings-dark-ollama-not-running", dark: true) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .local
            parts.catalog.show(.failed(.offline))
        }
    }

    @MainActor
    func testSettingsWithOpenAIAndNoKeyYet() throws {
        try snapshot(named: "settings-light-openai-no-key", dark: false) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .openai
        }
    }

    @MainActor
    func testSettingsWithOpenAIAndNoModelChosenYet() throws {
        try snapshot(named: "settings-light-openai-choose-model", dark: false) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .openai
            parts.settings.saveAPIKey("made-up-key-for-tests")
            parts.catalog.show(.loaded([AIModelChoice(id: "newer-chat-model", name: "newer-chat-model"), AIModelChoice(id: "older-chat-model", name: "older-chat-model")]))
        }
    }

    @MainActor
    func testSettingsWithAnotherServiceThatDoesNotListItsModels() throws {
        try snapshot(named: "settings-dark-other-typed-model", dark: true) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .other
            parts.settings.otherBaseURL = "http://localhost:1234/v1"
            parts.settings.talkModel = "a-model-name"
            parts.catalog.show(.failed(.modelNotFound))
        }
    }

    @MainActor
    func testSettingsWithAnotherServiceThatCannotBeReached() throws {
        try snapshot(named: "settings-light-other-unreachable", dark: false) { parts in
            parts.settings.aiEnabled = true
            parts.settings.provider = .other
            parts.settings.otherBaseURL = "http://localhost:1234/v1"
            parts.catalog.show(.failed(.offline))
        }
    }

    @MainActor
    func testTheListThatOpensUnderAModelName() throws {
        for dark in [false, true] {
            let list = ModelList(choices: Self.localModels, selected: "llama-test", isLight: !dark) { _ in }
                .padding(12)
                .background(dark ? Color.black : Color.white)
            attach(try renderOffscreen(list, dark: dark), named: dark ? "settings-model-list-dark" : "settings-model-list-light")
        }
    }

    // MARK: - Drawing

    // MARK: - Bringing entries from freewrite

    /// What a folder of 42 made-up entries looks like once it has been looked through.
    private static var madeUpPlan: ImportPlan {
        let items = (1...40).map { number in
            ImportPlan.Item(
                filename: "[\(UUID().uuidString)]-[2025-03-\(String(format: "%02d", number % 28 + 1))-08-00-00].md",
                videoPaths: number <= 3 ? ["Videos/made-up-\(number)"] : [],
                bytes: number <= 3 ? 103_000_000 : 27_000
            )
        }
        return ImportPlan(source: URL(fileURLWithPath: "/made-up/Freewrite"), items: items, alreadyHere: 2)
    }

    @MainActor
    func testSettingsAfterAFreewriteFolderWasPicked() throws {
        try snapshot(named: "settings-light-import-found", dark: false) { parts in
            parts.journalImport.show(.found(Self.madeUpPlan))
            XCTAssertEqual(parts.journalImport.line, "Found 42 entries and 3 videos (310 MB). 2 are already here.")
            XCTAssertEqual(parts.journalImport.copyWord, "Copy 40 entries")
        }
    }

    @MainActor
    func testSettingsWhileEntriesAreBeingCopied() throws {
        try snapshot(named: "settings-dark-import-copying", dark: true) { parts in
            parts.journalImport.show(.copying(done: 11, total: 40))
            XCTAssertEqual(parts.journalImport.line, "Copying 12 of 40…")
        }
    }

    @MainActor
    func testSettingsAfterEntriesWereCopied() throws {
        try snapshot(named: "settings-light-import-done", dark: false) { parts in
            parts.journalImport.show(.done(copied: 40, total: 40, failed: 0))
            XCTAssertEqual(parts.journalImport.line, "Copied 40 entries. They are in History now.")
        }
    }

    @MainActor
    func testSettingsWhenThePickedFolderHasNoEntries() throws {
        try snapshot(named: "settings-dark-import-nothing", dark: true) { parts in
            parts.journalImport.show(.nothing)
            XCTAssertEqual(parts.journalImport.line, "No freewrite entries in that folder. The folder is usually called Freewrite.")
        }
    }

    private struct Parts {
        let settings: AISettings
        let memory: MemoryStatus
        let versions: VersionSettings
        let catalog: ModelCatalog
        let journalImport: JournalImport
    }

    @MainActor
    private func snapshot(named name: String, dark: Bool, configure: (Parts) -> Void) throws {
        let box = SettingsBox()
        box.defaults.set(dark ? "dark" : "light", forKey: "colorScheme")

        let catalog = ModelCatalog(fetch: { [] })
        // Fixed from the start, so drawing the window never asks a service for anything.
        catalog.show(.idle)
        let parts = Parts(
            settings: box.settings(),
            memory: MemoryStatus(),
            versions: VersionSettings(defaults: box.defaults),
            catalog: catalog,
            // A throwaway journal folder, and a folder picker that is never opened.
            journalImport: JournalImport(
                root: FileManager.default.temporaryDirectory.appendingPathComponent("DearDiary-Tests-\(UUID().uuidString)", isDirectory: true),
                record: ImportRecord(defaults: box.defaults),
                pickFolder: { nil }
            )
        )
        configure(parts)

        let view = SettingsView(
            settings: parts.settings,
            memoryStatus: parts.memory,
            memoryActions: .none,
            versions: parts.versions,
            versionIndex: VersionIndex(),
            versionActions: .none,
            catalog: parts.catalog,
            connection: FakeProvider(),
            journalImport: parts.journalImport
        )
        .defaultAppStorage(box.defaults)

        attach(try renderOffscreen(view, dark: dark), named: name)
    }
}
