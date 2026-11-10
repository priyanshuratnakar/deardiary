//
//  AISettings.swift
//  Dear Diary
//
//  The AI choices the user makes in Settings: on or off, which service
//  answers, which models to use, and whether that service is ready (a key
//  saved, an address given, a model chosen). Model names live here as settings
//  and are never written into the networking code.
//

import Foundation
import Combine

/// The services that can answer when AI is on.
enum AIProviderKind: String, CaseIterable, Equatable {
    /// An open model running on this Mac through Ollama. Nothing leaves the Mac.
    case local
    case openai
    case claude
    /// Any other service that speaks the OpenAI chat format, at an address the user gives.
    case other

    /// The word shown in Settings.
    var title: String {
        switch self {
        case .local: return "On this Mac"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .other: return "Other"
        }
    }

    /// The service's name at the start of a sentence, for messages.
    var serviceName: String {
        switch self {
        case .local: return "Ollama"
        case .openai: return "OpenAI"
        case .claude: return "Claude"
        case .other: return "The AI service"
        }
    }

    /// The service's name in the middle of a sentence.
    var serviceNameInline: String {
        self == .other ? "the AI service" : serviceName
    }

    /// Who the account is with, for messages about keys and billing.
    var accountName: String? {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        case .local, .other: return nil
        }
    }

    /// True when nothing can be sent without an API key.
    var needsKey: Bool {
        self == .openai || self == .claude
    }

    /// True when a key may be saved (it is optional for "Other").
    var takesKey: Bool {
        self != .local
    }
}

/// The answer to "may the app talk to Claude right now?".
/// Every request to Claude asks this first.
enum AIAccess: Equatable {
    /// AI is switched off, or another service is chosen. Nothing may be sent.
    case off
    /// AI is on but no API key has been saved.
    case noKey
    /// AI is on and a key is available.
    case allowed(apiKey: String)
}

/// Where a request in the OpenAI chat format goes, and how it is signed.
struct AIEndpoint: Equatable {
    var kind: AIProviderKind
    /// For example https://api.openai.com/v1. Paths are added to this.
    var baseURL: URL
    /// Nil when the service needs no key.
    var apiKey: String?
}

/// The answer to "may the app talk to an OpenAI-style service right now?".
enum AIEndpointAccess: Equatable {
    case off
    case noKey
    case noAddress
    case allowed(AIEndpoint)
}

/// What still has to be done in Settings before Talk and Memory can work.
enum AISetupGap: Equatable {
    case key
    case address
    case model
}

/// Size limits, kept in one place.
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
    /// How much text a model on this Mac is asked to hold at once. Ollama's own
    /// default is far smaller and would silently cut off entries and memory.
    static let localContextTokens = 16_384
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

    /// Defaults used for Claude until the user picks a different model in Settings.
    /// The other services have no default: the user picks from the service's own list.
    static let defaultTalkModel = "claude-opus-5-5"
    static let defaultDigestModel = "claude-opus-5-5"

    /// Where each service lives. "Other" has no fixed address: the user gives one.
    static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    static let localBaseURL = URL(string: "http://localhost:11434")!

    private enum Key {
        static let enabled = "ai.enabled"
        static let provider = "ai.provider"
        static let memoryEnabled = "ai.memoryEnabled"
        static let memoryEnabledAt = "ai.memoryEnabledAt"
        static let otherBaseURL = "ai.other.baseURL"

        /// Claude keeps the names it has always had, so existing choices carry over.
        static func talkModel(_ kind: AIProviderKind) -> String {
            kind == .claude ? "ai.talkModel" : "ai.\(kind.rawValue).talkModel"
        }

        static func digestModel(_ kind: AIProviderKind) -> String {
            kind == .claude ? "ai.digestModel" : "ai.\(kind.rawValue).digestModel"
        }
    }

    private let defaults: UserDefaults
    private let keychain: Keychain

    /// Off until the user turns it on.
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.enabled) }
    }

    /// Which service answers. Claude until the user chooses another.
    @Published var provider: AIProviderKind {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: Key.provider)
            // Each service remembers its own models and its own key.
            talkModel = defaults.string(forKey: Key.talkModel(provider)) ?? Self.defaultTalkModel(for: provider)
            digestModel = defaults.string(forKey: Key.digestModel(provider)) ?? Self.defaultDigestModel(for: provider)
            hasAPIKey = keychain(for: provider)?.read() != nil
        }
    }

    /// Model used for talk mode, for the chosen service.
    @Published var talkModel: String {
        didSet { defaults.set(talkModel, forKey: Key.talkModel(provider)) }
    }

    /// Model used for building memory, for the chosen service.
    @Published var digestModel: String {
        didSet { defaults.set(digestModel, forKey: Key.digestModel(provider)) }
    }

    /// The address typed for "Other", for example http://localhost:1234/v1.
    @Published var otherBaseURL: String {
        didSet { defaults.set(otherBaseURL, forKey: Key.otherBaseURL) }
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

    /// True when a key for the chosen service is saved in the Keychain. The key itself is never kept here.
    @Published private(set) var hasAPIKey: Bool

    init(defaults: UserDefaults = .standard, keychain: Keychain = .apiKey) {
        self.defaults = defaults
        self.keychain = keychain
        let provider = AIProviderKind(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .claude
        self.aiEnabled = defaults.bool(forKey: Key.enabled)
        self.provider = provider
        self.talkModel = defaults.string(forKey: Key.talkModel(provider)) ?? Self.defaultTalkModel(for: provider)
        self.digestModel = defaults.string(forKey: Key.digestModel(provider)) ?? Self.defaultDigestModel(for: provider)
        self.otherBaseURL = defaults.string(forKey: Key.otherBaseURL) ?? ""
        self.memoryEnabled = defaults.bool(forKey: Key.memoryEnabled)
        self.hasAPIKey = Self.keychain(for: provider, claude: keychain)?.read() != nil
    }

    // MARK: - Models

    static func defaultTalkModel(for kind: AIProviderKind) -> String {
        kind == .claude ? defaultTalkModel : ""
    }

    static func defaultDigestModel(for kind: AIProviderKind) -> String {
        kind == .claude ? defaultDigestModel : ""
    }

    /// The talk model to send. For Claude a blank choice falls back to the default;
    /// for the other services it stays blank until the user picks one.
    var resolvedTalkModel: String {
        Self.cleaned(talkModel) ?? Self.defaultTalkModel(for: provider)
    }

    /// The memory model to send, with the same fallback.
    var resolvedDigestModel: String {
        Self.cleaned(digestModel) ?? Self.defaultDigestModel(for: provider)
    }

    // MARK: - Keys

    /// Each service keeps its key in its own Keychain item. Ollama has none.
    private static func keychain(for kind: AIProviderKind, claude: Keychain) -> Keychain? {
        switch kind {
        case .claude:
            return claude
        case .openai:
            return claude.sibling(named: "openai-api-key")
        case .other:
            return claude.sibling(named: "other-api-key")
        case .local:
            return nil
        }
    }

    private func keychain(for kind: AIProviderKind) -> Keychain? {
        Self.keychain(for: kind, claude: keychain)
    }

    /// Saves the key for the chosen service. Returns false if it was empty or could not be saved.
    @discardableResult
    func saveAPIKey(_ rawKey: String) -> Bool {
        guard let key = Self.cleaned(rawKey), let keychain = keychain(for: provider), keychain.save(key) else {
            return false
        }
        hasAPIKey = true
        return true
    }

    func removeAPIKey() {
        guard let keychain = keychain(for: provider) else { return }
        keychain.delete()
        hasAPIKey = keychain.read() != nil
    }

    // MARK: - Is everything set up?

    /// The address for "Other", if what was typed is a web address.
    static func address(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    /// What is still missing before Talk and Memory can work, or nil when nothing is.
    static func gap(provider: AIProviderKind, hasKey: Bool, otherBaseURL: String, talkModel: String) -> AISetupGap? {
        if provider.needsKey && !hasKey {
            return .key
        }
        if provider == .other && address(from: otherBaseURL) == nil {
            return .address
        }
        if (cleaned(talkModel) ?? defaultTalkModel(for: provider)).isEmpty {
            return .model
        }
        return nil
    }

    var setupGap: AISetupGap? {
        Self.gap(provider: provider, hasKey: hasAPIKey, otherBaseURL: otherBaseURL, talkModel: talkModel)
    }

    /// True when AI is on and the chosen service is fully set up. Talk and Memory show only then.
    var isReady: Bool {
        aiEnabled && setupGap == nil
    }

    /// Tells listeners at once whenever `isReady` changes.
    var readiness: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest4($aiEnabled, $provider, $hasAPIKey, $talkModel)
            .combineLatest($otherBaseURL)
            .map { values, address in
                values.0 && Self.gap(provider: values.1, hasKey: values.2, otherBaseURL: address, talkModel: values.3) == nil
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - The gates. Safe to call from any thread: they read the saved values directly.

    /// The service chosen in Settings, as saved.
    func savedProvider() -> AIProviderKind {
        AIProviderKind(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .claude
    }

    /// Decides whether a request may be sent to Claude. It does not touch the key unless AI is on.
    func access() -> AIAccess {
        guard defaults.bool(forKey: Key.enabled), savedProvider() == .claude else {
            return .off
        }
        guard let key = keychain.read() else {
            return .noKey
        }
        return .allowed(apiKey: key)
    }

    /// Decides whether a request may be sent to OpenAI or to the "Other" address.
    func endpointAccess() -> AIEndpointAccess {
        guard defaults.bool(forKey: Key.enabled) else {
            return .off
        }
        switch savedProvider() {
        case .openai:
            guard let key = keychain(for: .openai)?.read() else { return .noKey }
            return .allowed(AIEndpoint(kind: .openai, baseURL: Self.openAIBaseURL, apiKey: key))
        case .other:
            guard let url = Self.address(from: defaults.string(forKey: Key.otherBaseURL) ?? "") else { return .noAddress }
            return .allowed(AIEndpoint(kind: .other, baseURL: url, apiKey: keychain(for: .other)?.read()))
        case .claude, .local:
            return .off
        }
    }

    /// Decides whether a request may be sent to Ollama on this Mac.
    func localAccess() -> Bool {
        defaults.bool(forKey: Key.enabled) && savedProvider() == .local
    }

    // MARK: - For the memory engine, which works in the background

    /// True when memory may be built: AI on, memory on, and the chosen service set up
    /// with a memory model. Safe to call from any thread.
    func memoryAllowed() -> Bool {
        guard defaults.bool(forKey: Key.enabled), defaults.bool(forKey: Key.memoryEnabled) else {
            return false
        }
        let kind = savedProvider()
        if kind.needsKey, keychain(for: kind)?.read() == nil {
            return false
        }
        if kind == .other, Self.address(from: defaults.string(forKey: Key.otherBaseURL) ?? "") == nil {
            return false
        }
        return !savedDigestModel().isEmpty
    }

    /// When memory was last switched on. Entries last edited before this are
    /// left alone unless the user asks for a rebuild.
    func memoryEnabledSince() -> Date? {
        let stamp = defaults.double(forKey: Key.memoryEnabledAt)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The memory model as saved, read without touching anything the screen is using.
    func savedDigestModel() -> String {
        let kind = savedProvider()
        return Self.cleaned(defaults.string(forKey: Key.digestModel(kind)) ?? "") ?? Self.defaultDigestModel(for: kind)
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
