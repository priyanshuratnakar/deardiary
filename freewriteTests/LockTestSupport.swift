//
//  LockTestSupport.swift
//  freewriteTests
//
//  Helpers for the lock tests: a pretend check that answers from a script, so
//  macOS is never asked for Touch ID or a password, and a lock with throwaway
//  settings and a clock the test controls.
//

import Foundation
@testable import freewrite

/// Stands in for macOS's check. It answers from a script and notes what it was asked.
final class FakeAuthenticator: Authenticator, @unchecked Sendable {
    var available = true
    /// The answers to give, in order. With none left, the sheet counts as closed.
    var answers: [AuthenticationResult] = []
    private(set) var reasons: [String] = []

    init(_ answers: [AuthenticationResult] = []) {
        self.answers = answers
    }

    func isAvailable() -> Bool { available }

    func authenticate(reason: String) async -> AuthenticationResult {
        reasons.append(reason)
        return answers.isEmpty ? .cancelled : answers.removeFirst()
    }
}

/// A lock that exists only for one test.
@MainActor
final class LockBox {
    private let suiteName = "deardiary.tests.lock.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: LockSettings
    let check = FakeAuthenticator()
    /// The time the lock believes it is. Tests move it forward.
    var clock = MemoryWeek.day(9, hour: 21)

    init(on: Bool = true) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = LockSettings(defaults: defaults)
        settings.enabled = on
    }

    /// A fresh lock, as the app would make at launch.
    func lock() -> AppLock {
        AppLock(settings: settings, authenticator: check, now: { [unowned self] in self.clock }, watchesTheMac: false)
    }

    /// A lock that has already been opened by its owner.
    func openLock() async -> AppLock {
        let lock = self.lock()
        check.answers = [.allowed]
        await lock.unlock()
        return lock
    }

    func minutesPass(_ minutes: Double) {
        clock = clock.addingTimeInterval(minutes * 60)
    }

    /// Lets work started with `Task { }` on the main actor run.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
