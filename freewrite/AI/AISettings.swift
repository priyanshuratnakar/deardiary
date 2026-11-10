//
//  AISettings.swift
//  Dear Diary
//
//  The AI choices the user makes in Settings: on or off, which models to use,
//  and whether an API key is connected. Model names live here as settings and
//  are never written into the networking code.
//

import Foundation
import Combine

/// The answer to "may the app talk to Claude right now?".
/// Every network call asks this first.
enum AIAccess: Equatable {
    /// AI is switched off. Nothing may be sent.
    case off
    /// AI is on but no API key has been saved.
    case noKey
    /// AI is on and a key is available.
    case allowed(apiKey: String)
}

/// Size limits for replies, kept in one place.
enum AILimits {
    /// The Settings "Test connection" reply only needs a sentence.
    static let connectionTestMaxTokens = 1024
    /// Talk replies are short, but the model's private thinking counts towards
    /// this limit too, so it is set generously. It is a ceiling, not a cost.
    static let talkMaxTokens = 16_000
    /// A digest is a page or so of JSON, plus the model's private thinking.
    static let digestMaxTokens = 16_000
    /// The weekly tidy looks across all of memory, so its reply can be longer.
    static let tidyMaxTokens = 24_000
}

final class AISettings: ObservableObject {
    /// The app's settings. When the app is started by the test runner it gets a
    /// throwaway copy, so tests never read the real preferences or the real key.
    static let shared: AISettings = {
        guard StorageRoot.isRunningTests() else {
            return AISettings()
        }
        let suite = "deardiary.tests.host.\(UUID().uuidString)"
        return AISettings(
            defaults: UserDefaults(suiteName: suite) ?? .standard,
            keychain: Keychain(service: "com.priyanshuratnakar.deardiary.tests.host.\(UUID().uuidString)", account: "test")
        )
    }()

    /// Defaults used until the user types a different model name in Settings.
    static let defaultTalkModel = "claude-opus-5-5"
    static let defaultDigestModel = "claude-opus-5-5"

    private enum Key {
        static let enabled = "ai.enabled"
        static let talkModel = "ai.talkModel"
        static let digestModel = "ai.digestModel"
        static let memoryEnabled = "ai.memoryEnabled"
        static let memoryEnabledAt = "ai.memoryEnabledAt"
    }

    private let defaults: UserDefaults
    private let keychain: Keychain

    /// Off until the user turns it on.
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.enabled) }
    }

    /// Model used for talk mode.
    @Published var talkModel: String {
        didSet { defaults.set(talkModel, forKey: Key.talkModel) }
    }

    /// Model used for building memory.
    @Published var digestModel: String {
        didSet { defaults.set(digestModel, forKey: Key.digestModel) }
    }

    /// Whether entries are digested into memory. Off until the user turns it on,
    /// and separate from talk: talk works without it.
    @Published var memoryEnabled: Bool {
        didSet {
            defaults.set(memoryEnabled, forKey: Key.memoryEnabled)
            if memoryEnabled && !oldValue {
                // Remember the moment, so only entries written from now on are digested.
                defaults.set(Date().timeIntervalSince1970, forKey: Key.memoryEnabledAt)
            }
        }
    }

    /// True when a key is saved in the Keychain. The key itself is never kept here.
    @Published private(set) var hasAPIKey: Bool

    init(defaults: UserDefaults = .standard, keychain: Keychain = .apiKey) {
        self.defaults = defaults
        self.keychain = keychain
        self.aiEnabled = defaults.bool(forKey: Key.enabled)
        self.talkModel = defaults.string(forKey: Key.talkModel) ?? Self.defaultTalkModel
        self.digestModel = defaults.string(forKey: Key.digestModel) ?? Self.defaultDigestModel
        self.memoryEnabled = defaults.bool(forKey: Key.memoryEnabled)
        self.hasAPIKey = keychain.read() != nil
    }

    /// The talk model to send, falling back to the default if the field was left blank.
    var resolvedTalkModel: String {
        Self.cleaned(talkModel) ?? Self.defaultTalkModel
    }

    /// The memory model to send, falling back to the default if the field was left blank.
    var resolvedDigestModel: String {
        Self.cleaned(digestModel) ?? Self.defaultDigestModel
    }

    /// Saves the key to the Keychain. Returns false if it was empty or could not be saved.
    @discardableResult
    func saveAPIKey(_ rawKey: String) -> Bool {
        guard let key = Self.cleaned(rawKey), keychain.save(key) else {
            return false
        }
        hasAPIKey = true
        return true
    }

    func removeAPIKey() {
        keychain.delete()
        hasAPIKey = keychain.read() != nil
    }

    /// Decides whether a request may be sent. Safe to call from any thread:
    /// it reads the saved values directly and does not touch the key unless AI is on.
    func access() -> AIAccess {
        guard defaults.bool(forKey: Key.enabled) else {
            return .off
        }
        guard let key = keychain.read() else {
            return .noKey
        }
        return .allowed(apiKey: key)
    }

    // MARK: - For the memory engine, which works in the background

    /// True when memory may be built: AI on, memory on, and a key saved.
    /// Safe to call from any thread.
    func memoryAllowed() -> Bool {
        defaults.bool(forKey: Key.enabled)
            && defaults.bool(forKey: Key.memoryEnabled)
            && keychain.read() != nil
    }

    /// When memory was last switched on. Entries last edited before this are
    /// left alone unless the user asks for a rebuild.
    func memoryEnabledSince() -> Date? {
        let stamp = defaults.double(forKey: Key.memoryEnabledAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The memory model as saved, read without touching anything the screen is using.
    func savedDigestModel() -> String {
        Self.cleaned(defaults.string(forKey: Key.digestModel) ?? "") ?? Self.defaultDigestModel
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
