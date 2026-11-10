//
//  LockSettings.swift
//  Dear Diary
//
//  Whether Dear Diary locks, and how long it may sit in the background before
//  it does. Off until the user turns it on in Settings.
//

import Foundation
import Combine

final class LockSettings: ObservableObject {
    /// The app's setting. When the app is started by the test runner it gets a
    /// throwaway copy, so tests never read or change the real preference and
    /// the app under test never opens locked.
    static let shared: LockSettings = {
        guard StorageRoot.isRunningTests() else {
            return LockSettings()
        }
        return LockSettings(defaults: UserDefaults(suiteName: "deardiary.tests.host.lock.\(UUID().uuidString)") ?? .standard)
    }()

    /// The choices for how long Dear Diary may sit in the background before it locks.
    static let delays = [1, 5, 15, 30]
    static let defaultDelay = 5

    private enum Key {
        static let enabled = "lock.enabled"
        static let afterMinutes = "lock.afterMinutes"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    /// Minutes in the background before the lock closes.
    @Published var afterMinutes: Int {
        didSet { defaults.set(afterMinutes, forKey: Key.afterMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Key.enabled)
        let saved = defaults.integer(forKey: Key.afterMinutes)
        self.afterMinutes = Self.delays.contains(saved) ? saved : Self.defaultDelay
    }

    /// The next choice after the one in use, going round.
    func stepDelay() {
        let index = Self.delays.firstIndex(of: afterMinutes) ?? 0
        afterMinutes = Self.delays[(index + 1) % Self.delays.count]
    }

    /// The delay in words, for Settings.
    var delayInWords: String {
        afterMinutes == 1 ? "1 minute" : "\(afterMinutes) minutes"
    }
}
