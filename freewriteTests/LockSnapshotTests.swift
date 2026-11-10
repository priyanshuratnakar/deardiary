//
//  LockSnapshotTests.swift
//  freewriteTests
//
//  Draws the locked window off screen and attaches the pictures to the test
//  results: light and dark, with a problem line, and over the real writing
//  window to show that nothing of the page is left in view. macOS's check is
//  played by a script, so nothing is asked.
//

import XCTest
import SwiftUI
@testable import freewrite

final class LockSnapshotTests: XCTestCase {

    private let windowSize = CGSize(width: 1100, height: 632)

    @MainActor
    private func lockedBox(dark: Bool) -> (box: LockBox, lock: AppLock) {
        let box = LockBox()
        box.defaults.set(dark ? "dark" : "light", forKey: "colorScheme")
        return (box, box.lock())
    }

    @MainActor
    func testTheLockedWindowInLightMode() throws {
        let (box, lock) = lockedBox(dark: false)
        let view = LockScreen(lock: lock).defaultAppStorage(box.defaults)

        attach(try renderOffscreen(view, size: windowSize, dark: false), named: "lock-light")
    }

    @MainActor
    func testTheLockedWindowInDarkModeWithAProblemLine() async throws {
        let (box, lock) = lockedBox(dark: true)
        box.check.answers = [.failed]
        await lock.unlock()
        XCTAssertEqual(lock.problem, "Couldn't check that it's you. Try again.")
        let view = LockScreen(lock: lock).defaultAppStorage(box.defaults)

        attach(try renderOffscreen(view, size: windowSize, dark: true), named: "lock-dark-problem")
    }

    @MainActor
    func testTheLockCoversTheWholeWritingWindow() throws {
        let (box, lock) = lockedBox(dark: false)
        var page = ContentView()
        page.opensWithHistory = true
        let view = page
            .modifier(LockGate(lock: lock))
            .defaultAppStorage(box.defaults)

        attach(try renderOffscreen(view, size: windowSize, dark: false), named: "lock-over-the-page")
        XCTAssertTrue(lock.isLocked)
    }

    @MainActor
    func testAnOpenLockLeavesTheWindowAlone() async throws {
        let box = LockBox()
        let lock = await box.openLock()
        let view = ContentView().modifier(LockGate(lock: lock)).defaultAppStorage(box.defaults)

        attach(try renderOffscreen(view, size: windowSize, dark: false), named: "lock-open-page")
        XCTAssertFalse(lock.isLocked)
    }
}
