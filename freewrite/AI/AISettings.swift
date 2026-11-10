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
}

final class AISettings: ObservableObject {
    static let shared = AISettings()

    /// Defaults used until the user types a different model name in Settings.
    static let defaultTalkModel = "claude-opus-5-5"
    static let defaultDigestModel = "claude-opus-5-5"

    private enum Key {
        static let enabled = "ai.enabled"
        static let talkModel = "ai.talkModel"
        static let digestModel = "ai.digestModel"
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

    /// True when a key is saved in the Keychain. The key itself is never kept here.
    @Published private(set) var hasAPIKey: Bool

    init(defaults: UserDefaults = .standard, keychain: Keychain = .apiKey) {
        self.defaults = defaults
        self.keychain = keychain
        self.aiEnabled = defaults.bool(forKey: Key.enabled)
        self.talkModel = defaults.string(forKey: Key.talkModel) ?? Self.defaultTalkModel
        self.digestModel = defaults.string(forKey: Key.digestModel) ?? Self.defaultDigestModel
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

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
