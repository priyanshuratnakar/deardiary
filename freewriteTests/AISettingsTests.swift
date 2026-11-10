//
//  AISettingsTests.swift
//  freewriteTests
//
//  Checks the Keychain helper and the AI settings, using a throwaway Keychain
//  entry and a throwaway settings store so the real ones are never touched.
//

import Foundation
import Testing
@testable import freewrite

@Suite struct KeychainTests {

    private func throwawayKeychain() -> Keychain {
        Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString)", account: "test")
    }

    @Test func savesReadsReplacesAndDeletes() {
        let keychain = throwawayKeychain()
        defer { keychain.delete() }

        #expect(keychain.read() == nil)

        #expect(keychain.save("first-made-up-value"))
        #expect(keychain.read() == "first-made-up-value")

        #expect(keychain.save("second-made-up-value"))
        #expect(keychain.read() == "second-made-up-value")

        #expect(keychain.delete())
        #expect(keychain.read() == nil)
    }

    @Test func deletingSomethingThatIsNotThereIsFine() {
        #expect(throwawayKeychain().delete())
    }

    @Test func differentServicesDoNotSeeEachOther() {
        let first = throwawayKeychain()
        let second = throwawayKeychain()
        defer {
            first.delete()
            second.delete()
        }

        #expect(first.save("only-in-first"))
        #expect(second.read() == nil)
    }
}

@Suite struct AISettingsTests {

    /// A settings object backed by storage that exists only for one test.
    private final class Sandbox {
        let suiteName = "deardiary.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let keychain: Keychain

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            keychain = Keychain(service: "com.priyanshuratnakar.deardiary.tests.\(UUID().uuidString)", account: "test")
        }

        func makeSettings() -> AISettings {
            AISettings(defaults: defaults, keychain: keychain)
        }

        deinit {
            keychain.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test func startsWithAIOffAndNoKey() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        #expect(settings.aiEnabled == false)
        #expect(settings.hasAPIKey == false)
        #expect(settings.talkModel == AISettings.defaultTalkModel)
        #expect(settings.digestModel == AISettings.defaultDigestModel)
        #expect(settings.access() == .off)
    }

    @Test func aiOnWithoutAKeyIsNotAllowed() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        settings.aiEnabled = true

        #expect(settings.access() == .noKey)
    }

    @Test func aiOnWithAKeyIsAllowed() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        settings.aiEnabled = true
        #expect(settings.saveAPIKey("  made-up-key-for-tests \n"))

        #expect(settings.hasAPIKey)
        #expect(settings.access() == .allowed(apiKey: "made-up-key-for-tests"))
    }

    @Test func aiOffWinsEvenWhenAKeyIsSaved() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        #expect(settings.saveAPIKey("made-up-key-for-tests"))
        settings.aiEnabled = false

        #expect(settings.access() == .off)
    }

    @Test func emptyKeyIsNotSaved() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        #expect(settings.saveAPIKey("   ") == false)
        #expect(settings.hasAPIKey == false)
    }

    @Test func removingTheKeyBlocksRequestsAgain() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        settings.aiEnabled = true
        settings.saveAPIKey("made-up-key-for-tests")
        settings.removeAPIKey()

        #expect(settings.hasAPIKey == false)
        #expect(settings.access() == .noKey)
    }

    @Test func choicesAreRememberedNextLaunch() {
        let sandbox = Sandbox()
        let first = sandbox.makeSettings()
        first.aiEnabled = true
        first.talkModel = "model-for-talk"
        first.digestModel = "model-for-memory"
        first.saveAPIKey("made-up-key-for-tests")

        let second = sandbox.makeSettings()

        #expect(second.aiEnabled)
        #expect(second.talkModel == "model-for-talk")
        #expect(second.digestModel == "model-for-memory")
        #expect(second.hasAPIKey)
    }

    @Test func blankModelFieldsFallBackToTheDefaults() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        settings.talkModel = "   "
        settings.digestModel = ""

        #expect(settings.resolvedTalkModel == AISettings.defaultTalkModel)
        #expect(settings.resolvedDigestModel == AISettings.defaultDigestModel)

        settings.talkModel = "  model-for-talk  "
        #expect(settings.resolvedTalkModel == "model-for-talk")
    }

    @Test func theKeyIsNeverWrittenToTheSettingsStore() {
        let sandbox = Sandbox()
        let settings = sandbox.makeSettings()

        settings.aiEnabled = true
        settings.saveAPIKey("made-up-key-for-tests")

        let stored = sandbox.defaults.persistentDomain(forName: sandbox.suiteName) ?? [:]
        for value in stored.values {
            #expect(!"\(value)".contains("made-up-key-for-tests"))
        }
    }
}
