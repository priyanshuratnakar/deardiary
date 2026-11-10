//
//  VersionSettings.swift
//  Dear Diary
//
//  Whether versions are kept. Off until the user turns it on in Settings.
//  It has nothing to do with AI: versions never leave this Mac, and they work
//  with AI on or off.
//

import Foundation
import Combine

final class VersionSettings: ObservableObject {
    /// The app's setting. When the app is started by the test runner it gets a
    /// throwaway copy, so tests never read or change the real preference.
    static let shared: VersionSettings = {
        guard StorageRoot.isRunningTests() else {
            return VersionSettings()
        }
        return VersionSettings(defaults: UserDefaults(suiteName: "deardiary.tests.host.versions.\(UUID().uuidString)") ?? .standard)
    }()

    private enum Key {
        static let enabled = "versions.enabled"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Key.enabled)
    }

    /// True when versions are being kept. Safe to call from any thread:
    /// it reads the saved value directly.
    func isOn() -> Bool {
        defaults.bool(forKey: Key.enabled)
    }
}
